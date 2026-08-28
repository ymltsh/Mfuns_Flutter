import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/app_config.dart';
import 'download_policy.dart';
import 'download_repository.dart';
import 'download_storage.dart';
import 'download_status.dart';
import 'download_task.dart';
import 'download_transport.dart';

/// 任务控制块：暂停/取消时置位并中断进行中的请求。
class _TaskControl {
  var stopRequested = false;
  DownloadStatus? stopStatus;
  DownloadConnection? connection;
  bool get wantsStop => stopRequested;
}

/// 统一的下载管理器（任务 = 一个视频）：
/// 任务创建、排队、并发控制、任务内分P顺序下载、实时进度、
/// 暂停/恢复/取消/重试、完成与失败持久化、App 启动恢复。
class DownloadManager {
  DownloadManager({
    DownloadRepository? repository,
    DownloadTransport? transport,
    DownloadEnvironment? environment,
    DownloadPolicy? initialPolicy,
  })  : _repository = repository ??
            DownloadRepository(
              store: SqfliteDownloadTaskStore(),
              storage: DownloadStorage(),
            ),
        _transport = transport ?? HttpClientDownloadTransport(),
        _environment = environment ?? ConnectivityDownloadEnvironment(),
        _policy = initialPolicy ?? DownloadPolicy.defaults,
        _initialPolicyProvided = initialPolicy != null;

  /// 全局单例：App 启动时调用 [initialize]。
  static DownloadManager instance = DownloadManager();

  final DownloadRepository _repository;
  final DownloadTransport _transport;
  final DownloadEnvironment _environment;
  DownloadPolicy _policy;
  final bool _initialPolicyProvided;

  final Map<String, _TaskControl> _controls = {};
  final Set<String> _active = {};
  final Map<String, Future<void>> _runners = {};
  final List<String> _queue = [];
  var _initialized = false;
  StreamSubscription<DownloadNetworkType>? _networkSubscription;
  bool _wakelockHeld = false;

  /// 连接失败自动重试次数（瞬时网络错误，指数退避）。
  static const maxAutoRetries = 3;

  /// 自动重试退避基数（2^retry 倍）；测试可调小。
  Duration autoRetryBase = const Duration(seconds: 2);

  /// 单块写入后更新进度/触发重试检查的阈值。
  static const progressReportThreshold = 256 * 1024;

  DownloadPolicy get policy => _policy;

  bool get isInitialized => _initialized;

  int get activeCount => _active.length;

  int get queuedCount => _queue.length;

  bool get isDownloading => _active.isNotEmpty || _queue.isNotEmpty;

  /// 测试用：访问底层数据层。
  @visibleForTesting
  DownloadRepository get repositoryForTest => _repository;

  Duration _retryDelay(int retry) => autoRetryBase * (1 << retry);

  /// 初始化：加载策略 → 恢复数据库任务 → 订阅网络变化 → 开始排队下载。
  Future<void> initialize() async {
    if (_initialized) return;
    // 显式注入的策略优先；否则读取持久化偏好。
    if (!_initialPolicyProvided) {
      _policy = await DownloadPreferences.load();
    }
    await _repository.initialize();
    _initialized = true;
    _queue
      ..clear()
      ..addAll(_repository.tasks
          .where((task) => task.status.isActive)
          .map((task) => task.taskId));
    _subscribeNetwork();
    _pump();
  }

  Future<void> _subscribeNetwork() async {
    final changes = _environment.networkChanges;
    if (changes == null) return;
    try {
      _networkSubscription = changes.listen(_onNetworkChanged);
    } catch (_) {
      // 平台不支持时忽略。
    }
  }

  /// 网络切换到移动网络且开启了“仅 Wi-Fi”时，自动暂停进行中的下载。
  Future<void> _onNetworkChanged(DownloadNetworkType type) async {
    if (!_policy.wifiOnly || !type.isMobile) return;
    final running = [..._active];
    for (final taskId in running) {
      await pause(taskId);
    }
  }

  /// 创建下载任务（自动去重）并加入队列。
  ///
  /// [force] 为 true 时忽略“仅 Wi-Fi”限制（用户在移动网络提示后确认继续）。
  /// 返回任务 ID。
  Future<String> enqueue(DownloadRequest request, {bool force = false}) async {
    if (!_initialized) await initialize();
    if (!force && _policy.wifiOnly) {
      final network = await _environment.currentNetwork();
      if (network.isMobile) {
        throw const DownloadException(
          '当前为移动网络，请连接 Wi-Fi 或手动确认后继续下载',
          kind: DownloadErrorKind.network,
        );
      }
    }
    final task = await _repository.createTask(request);
    if (task.status.isActive && !_queue.contains(task.taskId)) {
      _queue.add(task.taskId);
      _pump();
    }
    return task.taskId;
  }

  /// 暂停：进行中 → 中断当前分P并标记 paused；排队中 → 直接标记 paused。
  Future<void> pause(String taskId) async {
    final current = await _repository.task(taskId);
    if (current == null || current.status.isTerminal) return;
    // 立即登记控制块，避免与任务启动竞态（先置位再中断）。
    final control = _controls.putIfAbsent(taskId, _TaskControl.new);
    if (control.wantsStop) return;
    control.stopRequested = true;
    control.stopStatus = DownloadStatus.paused;
    control.connection?.abort();
    if (!_active.contains(taskId)) {
      _queue.remove(taskId);
      final task = await _repository.task(taskId);
      if (task != null && task.status.isActive) {
        await _repository.setTaskStatus(task, DownloadStatus.paused);
      }
    }
    _pump();
    // 等待在途任务收尾（控制块移除）后再返回，保证后续 resume 不被旧控制块拦截。
    await _runners[taskId];
  }

  /// 恢复：暂停/失败的任务重新排队。
  Future<void> resume(String taskId) async {
    if (_controls.containsKey(taskId)) return;
    final task = await _repository.task(taskId);
    if (task == null) return;
    if (task.status == DownloadStatus.completed ||
        task.status == DownloadStatus.canceled) {
      return;
    }
    if (task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed &&
        !task.status.isActive) {
      return;
    }
    await _repository.setTaskStatus(task, DownloadStatus.pending,
        errorMessage: '');
    if (!_queue.contains(taskId)) _queue.add(taskId);
    _pump();
  }

  /// 重试：失败/取消的任务回到排队态，未完成分P从断点继续。
  Future<void> retry(String taskId) async {
    final task = await _repository.task(taskId);
    if (task == null || task.status == DownloadStatus.completed) return;
    if (task.status.isActive || task.status == DownloadStatus.paused) {
      return resume(taskId);
    }
    // 未完成分P回到排队态，已完成分P保留。
    final resetParts = task.parts
        .map((part) => part.isPlayable
            ? part
            : part.copyWith(
                status: DownloadStatus.pending,
                errorMessage: '',
              ))
        .toList(growable: false);
    await _repository.updateParts(taskId, resetParts);
    final resetTask = await _repository.task(taskId);
    if (resetTask != null) {
      await _repository.setTaskStatus(resetTask, DownloadStatus.pending,
          errorMessage: '');
    }
    if (!_queue.contains(taskId)) _queue.add(taskId);
    _pump();
  }

  /// 取消：中断进行中的任务并删除未完成分P的临时文件，保留任务记录（可重试）。
  Future<void> cancel(String taskId) async {
    final current = await _repository.task(taskId);
    if (current == null ||
        current.status.isTerminal ||
        current.status == DownloadStatus.paused) {
      return;
    }
    final control = _controls.putIfAbsent(taskId, _TaskControl.new);
    if (control.wantsStop) return;
    control.stopRequested = true;
    control.stopStatus = DownloadStatus.canceled;
    control.connection?.abort();
    if (!_active.contains(taskId)) {
      _queue.remove(taskId);
      final task = await _repository.task(taskId);
      if (task == null) return;
      await _repository.setTaskStatus(task, DownloadStatus.canceled);
      for (final part in task.parts) {
        if (part.isPlayable) continue;
        try {
          final temp = File(part.tempFilePath);
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
      }
    }
    _pump();
    await _runners[taskId];
  }

  /// 删除任务：中断下载并移除数据库记录与本地文件。
  Future<void> delete(String taskId) async {
    final control = _controls.remove(taskId);
    if (control != null && control.wantsStop) return;
    if (control != null) {
      control.stopRequested = true;
      control.connection?.abort();
    }
    _queue.remove(taskId);
    await _repository.deleteTask(taskId);
    if (control != null) _active.remove(taskId);
    _syncWakelock();
    _pump();
  }

  Future<List<DownloadTask>> getTasks() async => _repository.tasks;

  Stream<List<DownloadTask>> watchTasks() => _repository.watchTasks();

  Future<void> updatePolicy(DownloadPolicy policy) async {
    _policy = policy;
    await DownloadPreferences.save(policy);
    if (policy.wifiOnly) {
      final network = await _environment.currentNetwork();
      if (network.isMobile) {
        await _onNetworkChanged(network);
      }
    } else {
      _pump();
    }
  }

  /// 探测各分P媒体文件大小（`Range: bytes=0-0`），不支持 Range 时返回 null。
  Future<int?> probePartSize(DownloadPartSource source) async {
    try {
      final connection = await _transport.connect(
        Uri.parse(source.url),
        headers: _mediaHeaders(),
        offset: 0,
      );
      try {
        if (connection.statusCode == 206 &&
            connection.contentRangeTotal != null &&
            connection.contentRangeTotal! > 0) {
          return connection.contentRangeTotal;
        }
        if (connection.statusCode == 200 &&
            connection.contentLength != null &&
            connection.contentLength! > 0) {
          return connection.contentLength;
        }
        return null;
      } finally {
        connection.abort();
      }
    } catch (_) {
      return null;
    }
  }

  /// 探测整个视频预计大小：各分P大小求和（未知的分P忽略）。
  Future<int?> probeVideoSize(DownloadRequest request) async {
    var total = 0;
    var known = 0;
    for (final source in request.parts) {
      final size = await probePartSize(source);
      if (size != null) {
        total += size;
        known++;
      }
    }
    return known > 0 ? total : null;
  }

  /// 查询 `videoId + quality` 对应的任务（含失败/已完成等所有状态）。
  Future<DownloadTask?> findTask({
    required int videoId,
    required String quality,
  }) =>
      _repository.findTask(videoId: videoId, quality: quality);

  /// 查询 `videoId + part + quality` 对应的可离线播放文件。
  Future<String?> localFileFor({
    required int videoId,
    required int part,
    required String quality,
  }) =>
      _repository.localFileFor(videoId: videoId, part: part, quality: quality);

  Future<int> usedSpaceBytes() => _repository.usedSpaceBytes();

  /// 媒体请求头：User-Agent / Referer，绝不含社区登录凭证。
  Map<String, String> _mediaHeaders() => {
        HttpHeaders.userAgentHeader: AppConfig.userAgent,
        HttpHeaders.refererHeader: 'https://${AppConfig.apiHost}/',
      };

  /// 队列调度：在最大并发数内启动排队任务。
  void _pump() {
    if (!_initialized) return;
    while (_active.length < _policy.maxConcurrent && _queue.isNotEmpty) {
      final taskId = _queue.removeAt(0);
      if (_active.contains(taskId)) continue;
      final task = _taskById(taskId);
      if (task == null) continue;
      if (!task.status.isActive) continue;
      _active.add(taskId);
      final runner = _runTask(taskId).whenComplete(() {
        _runners.remove(taskId);
      });
      _runners[taskId] = runner;
    }
    _syncWakelock();
  }

  DownloadTask? _taskById(String taskId) {
    for (final task in _repository.tasks) {
      if (task.taskId == taskId) return task;
    }
    return null;
  }

  void _syncWakelock() {
    final shouldHold = _active.isNotEmpty || _queue.isNotEmpty;
    if (shouldHold == _wakelockHeld) return;
    _wakelockHeld = shouldHold;
    // 移动平台保持 CPU 唤醒，确保退后台/锁屏时下载继续。
    final future = shouldHold ? WakelockPlus.enable() : WakelockPlus.disable();
    unawaited(future.then<void>((_) {}, onError: (_) {}));
  }

  /// 释放订阅并等待在途任务收尾（测试用）。
  Future<void> dispose() async {
    await _networkSubscription?.cancel();
    _networkSubscription = null;
    for (final taskId in [..._active]) {
      await cancel(taskId);
    }
    await Future.wait([..._runners.values]);
  }

  /// 执行单个任务：任务内分P顺序下载，全部完成后任务 completed。
  ///
  /// 每轮从数据层读取最新分P列表，任务运行期间补下的分P也会被下载。
  Future<void> _runTask(String taskId) async {
    var task = await _repository.task(taskId);
    if (task == null) return;
    final control = _controls.putIfAbsent(taskId, _TaskControl.new);
    await _repository.setTaskStatus(task, DownloadStatus.downloading);
    try {
      while (true) {
        if (control.wantsStop) throw const DownloadCancelledException();
        final latest = await _repository.task(taskId);
        if (latest == null) throw const DownloadCancelledException();
        final next = latest.parts.where((p) => !p.isPlayable).firstOrNull;
        if (next == null) break; // 全部分P完成
        await _repository.setPartStatus(
            latest, next.part, DownloadStatus.downloading);
        final success = await _downloadPartLoop(taskId, next, control);
        if (!success) return; // 失败已落库
        // 分P下载完成：重命名 .part → 正式文件；全部分P完成后任务自动 completed。
        final current = await _repository.task(taskId);
        if (current == null) throw const DownloadCancelledException();
        final updated = await _repository.completePart(current, next.part);
        if (updated?.status == DownloadStatus.completed) return;
      }
    } on DownloadCancelledException {
      await _markStopped(taskId, control);
    } on DownloadException catch (error) {
      if (control.wantsStop) {
        await _markStopped(taskId, control);
        return;
      }
      await _markTaskFailed(taskId, error.message);
    } catch (error) {
      if (control.wantsStop) {
        await _markStopped(taskId, control);
        return;
      }
      await _markTaskFailed(taskId, '下载失败：$error');
    } finally {
      _active.remove(taskId);
      _controls.remove(taskId);
      _syncWakelock();
      _pump();
    }
  }

  /// 任务失败落库：未完成分P回到 pending（等待重试），已完成分P保留。
  Future<void> _markTaskFailed(String taskId, String message) async {
    final stoppedTask = await _repository.task(taskId);
    if (stoppedTask == null) return;
    final parts = stoppedTask.parts
        .map((part) => part.isPlayable
            ? part
            : part.copyWith(
                status: DownloadStatus.pending,
                errorMessage: '',
              ))
        .toList(growable: false);
    await _repository.updateParts(taskId, parts);
    final latest = await _repository.task(taskId);
    if (latest != null) {
      await _repository.setTaskStatus(latest, DownloadStatus.failed,
          errorMessage: message);
    }
  }

  /// 暂停/取消落库：取消时同时删除未完成分P的临时文件
  /// （先删文件再落状态，保证观察者收到事件时临时文件已清理）。
  Future<void> _markStopped(String taskId, _TaskControl control) async {
    final stopped = control.stopStatus;
    final stoppedTask = await _repository.task(taskId);
    if (stoppedTask == null) return;
    if (stopped == DownloadStatus.canceled) {
      final parts = stoppedTask.parts
          .map((part) => part.isPlayable
              ? part
              : part.copyWith(status: DownloadStatus.canceled))
          .toList(growable: false);
      for (final part in parts) {
        if (part.isPlayable) continue;
        try {
          final temp = File(part.tempFilePath);
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
      }
      await _upsertPartsAndStatus(taskId, parts, DownloadStatus.canceled);
    } else {
      final parts = stoppedTask.parts
          .map((part) => part.status == DownloadStatus.downloading
              ? part.copyWith(status: DownloadStatus.paused)
              : part)
          .toList(growable: false);
      await _upsertPartsAndStatus(taskId, parts, DownloadStatus.paused);
    }
  }

  Future<void> _upsertPartsAndStatus(
    String taskId,
    List<DownloadPartTask> parts,
    DownloadStatus status,
  ) async {
    final task = await _repository.task(taskId);
    if (task == null) return;
    await _repository.updateParts(taskId, parts);
    final latest = await _repository.task(taskId);
    if (latest != null) {
      await _repository.setTaskStatus(latest, status);
    }
  }

  /// 单个分P的下载循环：处理 206/200/416、断点续传与瞬时错误的
  /// 指数退避自动重试。
  Future<bool> _downloadPartLoop(
    String taskId,
    DownloadPartTask part,
    _TaskControl control,
  ) async {
    final headers = _mediaHeaders();
    var retries = 0;
    while (true) {
      if (control.wantsStop) throw const DownloadCancelledException();
      try {
        final result = await _downloadPartAttempt(taskId, part, headers, control);
        if (result) return true;
        // 本次响应结束但未达总大小（服务器提前截断）：续传重试。
        if (retries >= maxAutoRetries) {
          throw const DownloadException(
            '下载中断且自动重试次数已用完，请手动重试',
            kind: DownloadErrorKind.network,
          );
        }
        retries++;
        await Future<void>.delayed(_retryDelay(retries));
      } on DownloadException catch (error) {
        if (control.wantsStop) throw const DownloadCancelledException();
        if (!error.isTransient || retries >= maxAutoRetries) rethrow;
        // 瞬时网络错误（断网/超时）：指数退避后自动续传。
        retries++;
        await Future<void>.delayed(_retryDelay(retries));
      }
    }
  }

  /// 单次分P下载尝试：返回是否已达到完整大小。
  Future<bool> _downloadPartAttempt(
    String taskId,
    DownloadPartTask part,
    Map<String, String> headers,
    _TaskControl control,
  ) async {
    final task = await _repository.task(taskId);
    if (task == null) throw const DownloadCancelledException();
    final currentPart = task.parts.where((p) => p.part == part.part).firstOrNull;
    if (currentPart == null) throw const DownloadCancelledException();
    if (currentPart.isPlayable) return true;
    // 断点：以 .part 文件实际大小为准（覆盖记录，避免记录与文件不一致）。
    var offset = 0;
    try {
      final temp = File(currentPart.tempFilePath);
      if (await temp.exists()) {
        offset = await temp.length();
      }
    } catch (_) {
      offset = 0;
    }
    if (currentPart.totalBytes > 0 && offset >= currentPart.totalBytes) {
      return true;
    }

    final connection = await _transport.connect(
      Uri.parse(currentPart.sourceUrl),
      headers: headers,
      offset: offset,
    );
    control.connection = connection;
    // 连接建立期间可能已收到暂停/取消请求：立即中断，避免悬挂。
    if (control.wantsStop) {
      connection.abort();
      throw const DownloadCancelledException();
    }
    try {
      switch (connection.statusCode) {
        case 206:
          break;
        case 200:
          // 服务器忽略 Range：从零重新完整下载。
          if (offset > 0) {
            final temp = File(currentPart.tempFilePath);
            if (await temp.exists()) await temp.delete();
            offset = 0;
          }
          if (connection.contentLength != null) {
            await _repository.updatePartProgress(
              task,
              currentPart.part,
              downloadedBytes: offset,
              totalBytes: connection.contentLength ?? 0,
            );
          }
          break;
        case 416:
          // Range 不可满足：已知总大小且文件已完整 → 完成；否则从头下载。
          final rangeTotal = connection.contentRangeTotal ?? 0;
          if (rangeTotal > 0 && offset >= rangeTotal) return true;
          final temp = File(currentPart.tempFilePath);
          if (await temp.exists()) await temp.delete();
          await _repository.updatePartProgress(
            task,
            currentPart.part,
            downloadedBytes: 0,
            totalBytes: rangeTotal,
          );
          return false;
        case 403:
          throw const DownloadException(
            '媒体地址访问被拒绝（403），请稍后重试',
            kind: DownloadErrorKind.auth,
          );
        case 404:
          throw const DownloadException(
            '播放地址已失效（404），请重新获取后重试',
            kind: DownloadErrorKind.notFound,
          );
        default:
          throw DownloadException(
            '下载失败（HTTP ${connection.statusCode}）',
            kind: DownloadErrorKind.http,
          );
      }

      // 总大小：Content-Range total 优先，其次 Content-Length + offset。
      final rangeTotal = connection.contentRangeTotal;
      final total = (rangeTotal != null && rangeTotal > 0)
          ? rangeTotal
          : (connection.contentLength != null &&
                  connection.contentLength! >= 0)
              ? offset + connection.contentLength!
              : currentPart.totalBytes;

      final finalLength = await _appendPartBody(
        taskId,
        currentPart,
        connection,
        offset,
        total,
        control,
      );
      if (control.wantsStop) throw const DownloadCancelledException();
      if (total > 0 && finalLength >= total) return true;
      // 总大小未知：响应结束即认为完成（单文件直链场景）。
      if (total <= 0) return true;
      // 响应体提前结束：交给外层续传重试。
      return false;
    } finally {
      connection.abort();
      control.connection = null;
    }
  }

  /// 把响应体追加写入分P的 `.part` 文件，实时上报进度与速度。
  Future<int> _appendPartBody(
    String taskId,
    DownloadPartTask part,
    DownloadConnection connection,
    int startOffset,
    int totalBytes,
    _TaskControl control,
  ) async {
    final temp = File(part.tempFilePath);
    await temp.parent.create(recursive: true);
    final raf = await temp.open(mode: FileMode.append);
    var offset = startOffset;
    var lastReport = offset;
    var lastReportTime = DateTime.now();
    var speed = 0.0;
    var lastSpeedTime = DateTime.now();
    try {
      await for (final chunk in connection.body.timeout(
        const Duration(seconds: 30),
        onTimeout: (sink) => sink.addError(
          const DownloadException(
            '下载超时（30 秒无数据），请检查网络后重试',
            kind: DownloadErrorKind.timeout,
          ),
        ),
      )) {
        if (control.wantsStop) throw const DownloadCancelledException();
        try {
          await raf.writeFrom(chunk);
        } on FileSystemException catch (error) {
          throw DownloadException(
            '文件写入失败：${error.message}',
            kind: DownloadErrorKind.disk,
          );
        } on IOException catch (error) {
          throw DownloadException(
            '磁盘写入失败：$error',
            kind: DownloadErrorKind.disk,
          );
        }
        offset += chunk.length;
        final now = DateTime.now();
        final delta = now.difference(lastSpeedTime).inMilliseconds;
        if (delta >= 500) {
          final instant =
              chunk.length / (delta / 1000).clamp(0.25, double.infinity);
          speed = speed <= 0 ? instant : speed * 0.7 + instant * 0.3;
          lastSpeedTime = now;
        }
        if (offset - lastReport >= progressReportThreshold ||
            now.difference(lastReportTime).inMilliseconds >= 500) {
          lastReport = offset;
          lastReportTime = now;
          final latest = await _repository.task(taskId);
          if (latest != null) {
            await _repository.updatePartProgress(
              latest,
              part.part,
              downloadedBytes: offset,
              totalBytes: totalBytes,
              speed: speed,
            );
          }
        }
      }
    } finally {
      await raf.close();
    }
    final latest = await _repository.task(taskId);
    if (latest != null) {
      await _repository.updatePartProgress(
        latest,
        part.part,
        downloadedBytes: offset,
        totalBytes: totalBytes,
        speed: 0,
      );
    }
    return offset;
  }
}
