import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/download/download_policy.dart';
import 'package:mfuns_flutter/core/download/download_status.dart';
import 'package:mfuns_flutter/core/download/download_storage.dart';
import 'package:mfuns_flutter/core/download/download_task.dart';
import 'package:mfuns_flutter/core/download/download_transport.dart';

/// 测试环境：固定为 Wi-Fi（可在测试中切换）。
class FakeDownloadEnvironment implements DownloadEnvironment {
  FakeDownloadEnvironment({DownloadNetworkType type = DownloadNetworkType.wifi})
      : _current = type;

  DownloadNetworkType _current;
  final _controller = StreamController<DownloadNetworkType>.broadcast();

  void setNetwork(DownloadNetworkType type) {
    _current = type;
    _controller.add(type);
  }

  @override
  Future<DownloadNetworkType> currentNetwork() async => _current;

  @override
  Stream<DownloadNetworkType>? get networkChanges => _controller.stream;
}

/// 可编程的下载连接替身。
class FakeDownloadConnection implements DownloadConnection {
  FakeDownloadConnection({
    required this.statusCode,
    this.contentLength,
    this.contentRangeStart,
    this.contentRangeEnd,
    this.contentRangeTotal,
    Stream<List<int>>? body,
  }) : body = body ?? const Stream<List<int>>.empty();

  @override
  final int statusCode;

  @override
  final int? contentLength;

  @override
  final int? contentRangeStart;

  @override
  final int? contentRangeEnd;

  @override
  final int? contentRangeTotal;

  @override
  final Stream<List<int>> body;

  var aborted = false;

  @override
  void abort() {
    aborted = true;
  }
}

/// 场景构建：按 URL 的 offset 返回对应响应。
typedef ResponseBuilder = Future<DownloadConnection> Function(int offset);

/// 可编程下载传输替身：
/// - [responders]：每次 connect 依次取用，末尾不足时重复最后一个。
/// - [failures]：在指定调用次数时抛出瞬时网络异常（模拟断网）。
class FakeDownloadTransport implements DownloadTransport {
  FakeDownloadTransport({List<ResponseBuilder>? responders})
      : responders = responders ?? [];

  List<ResponseBuilder> responders;
  final List<int> requestedOffsets = [];
  final List<Map<String, String>> requestedHeaders = [];
  int callCount = 0;

  /// 第 [call] 次调用（1 起）抛出网络异常。
  Set<int> failures = {};
  DownloadErrorKind failureKind = DownloadErrorKind.network;

  @override
  Future<DownloadConnection> connect(
    Uri uri, {
    required Map<String, String> headers,
    required int offset,
  }) async {
    callCount++;
    requestedOffsets.add(offset);
    requestedHeaders.add(headers);
    if (failures.contains(callCount)) {
      throw DownloadException(
        '模拟网络中断',
        kind: failureKind,
      );
    }
    if (responders.isEmpty) {
      return FakeDownloadConnection(statusCode: 200, contentLength: 0);
    }
    final index = callCount - 1 < responders.length
        ? callCount - 1
        : responders.length - 1;
    return responders[index](offset);
  }

  /// 便捷构造：206 分段响应。
  static ResponseBuilder partial(
    Uint8List fullBody, {
    int chunkSize = 64 * 1024,
    bool ignoreRange = false,
  }) {
    return (offset) async {
      if (ignoreRange || offset <= 0) {
        return FakeDownloadConnection(
          statusCode: 200,
          contentLength: fullBody.length,
          body: _chunks(fullBody, chunkSize),
        );
      }
      final remaining = fullBody.sublist(
          offset < fullBody.length ? offset : fullBody.length);
      return FakeDownloadConnection(
        statusCode: 206,
        contentLength: remaining.length,
        contentRangeStart: offset,
        contentRangeEnd: fullBody.length - 1,
        contentRangeTotal: fullBody.length,
        body: _chunks(remaining, chunkSize),
      );
    };
  }

  static Stream<List<int>> _chunks(Uint8List bytes, int chunkSize) async* {
    var index = 0;
    while (index < bytes.length) {
      final end = (index + chunkSize).clamp(0, bytes.length);
      yield Uint8List.sublistView(bytes, index, end);
      index = end;
    }
  }
}

/// 可手动放行的下载连接：用于并发数/暂停等时序测试。
class SlowDownloadConnection implements DownloadConnection {
  SlowDownloadConnection({
    required this.statusCode,
    required this.remaining,
    this.contentRangeTotal,
    this.contentLength,
  });

  @override
  final int statusCode;
  final Uint8List remaining;
  @override
  final int? contentRangeTotal;
  @override
  final int? contentLength;

  final StreamController<List<int>> _controller = StreamController();

  /// 放行剩余数据并结束响应。
  void release() {
    if (!_controller.isClosed) {
      _controller.add(remaining);
      _controller.close();
    }
  }

  @override
  int? get contentRangeStart => null;

  @override
  int? get contentRangeEnd => null;

  @override
  Stream<List<int>> get body => _controller.stream;

  var aborted = false;

  @override
  void abort() {
    aborted = true;
    if (!_controller.isClosed) _controller.close();
  }
}

/// 手动控制时序的传输替身：连接挂起直到 [release] 放行。
class SlowDownloadTransport implements DownloadTransport {
  SlowDownloadTransport({required this.fullBody});

  final Uint8List fullBody;
  final List<SlowDownloadConnection> connections = [];
  int callCount = 0;

  @override
  Future<DownloadConnection> connect(
    Uri uri, {
    required Map<String, String> headers,
    required int offset,
  }) async {
    callCount++;
    final remaining = offset >= fullBody.length
        ? Uint8List(0)
        : Uint8List.sublistView(fullBody, offset);
    final connection = SlowDownloadConnection(
      statusCode: offset > 0 ? 206 : 200,
      remaining: remaining,
      contentRangeTotal: fullBody.length,
      contentLength: remaining.length,
    );
    connections.add(connection);
    return connection;
  }

  void releaseAll() {
    for (final connection in connections) {
      connection.release();
    }
  }
}

/// 便捷方法：构造分P明细。
DownloadPartTask makePart({
  int part = 1,
  String sourceUrl = 'https://cdn.example.com/video.mp4?sign=abc',
  String? filePath,
  String? tempFilePath,
  int downloadedBytes = 0,
  int totalBytes = 0,
  DownloadStatus status = DownloadStatus.pending,
  String errorMessage = '',
}) {
  final base = tempFilePath ?? 'p${part}_1080p.mp4.part';
  return DownloadPartTask(
    part: part,
    sourceUrl: sourceUrl,
    filePath: filePath ?? base.replaceFirst(RegExp(r'\.part$'), ''),
    tempFilePath: base,
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    status: status,
    errorMessage: errorMessage,
  );
}

/// 便捷方法：构造视频级下载任务（含分P明细）。
DownloadTask makeTask({
  int videoId = 1,
  String quality = '1080p',
  String qualityLabel = '1080P',
  String title = '测试视频',
  String cover = '',
  DownloadStatus status = DownloadStatus.pending,
  List<DownloadPartTask>? parts,
  int downloadedBytes = 0,
  int totalBytes = 0,
  String errorMessage = '',
}) {
  final id = DownloadTask.buildTaskId(videoId: videoId, quality: quality);
  final partList = parts ??
      [makePart(part: 1, status: status == DownloadStatus.completed ? DownloadStatus.completed : DownloadStatus.pending)];
  return DownloadTask(
    taskId: id,
    videoId: videoId,
    title: title,
    cover: cover,
    quality: quality,
    qualityLabel: qualityLabel,
    status: status,
    downloadedBytes: downloadedBytes,
    totalBytes: totalBytes,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
    errorMessage: errorMessage,
    parts: partList,
  );
}

/// 便捷方法：构造视频级下载请求（分P直链）。
DownloadRequest makeRequest({
  int videoId = 1,
  String quality = '1080p',
  String qualityLabel = '1080P',
  String title = '测试视频',
  String cover = '',
  List<DownloadPartSource>? parts,
}) {
  return DownloadRequest(
    videoId: videoId,
    title: title,
    cover: cover,
    quality: quality,
    qualityLabel: qualityLabel,
    parts: parts ??
        [
          DownloadPartSource(
              part: 1, url: 'https://cdn.example.com/$videoId/p1.mp4'),
        ],
  );
}

/// 任务状态观察器：订阅任务流并缓冲最新状态，支持等待指定状态。
///
/// 必须在触发任务动作**之前**创建，避免广播流错过早期事件。
class TaskWatcher {
  TaskWatcher(Stream<List<DownloadTask>> stream) {
    _subscription = stream.listen(_onTasks);
  }

  late final StreamSubscription<List<DownloadTask>> _subscription;
  final Map<String, DownloadTask> _latest = {};
  final List<Completer<void>> _waiters = [];

  void _onTasks(List<DownloadTask> tasks) {
    for (final task in tasks) {
      _latest[task.taskId] = task;
    }
    final fired = [..._waiters];
    _waiters.clear();
    for (final waiter in fired) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  DownloadTask? current(String taskId) => _latest[taskId];

  /// 等待任务到达指定状态。
  Future<DownloadTask> waitFor(
    String taskId,
    DownloadStatus status, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final current = _latest[taskId];
    if (current != null && current.status == status) return current;
    final completer = Completer<DownloadTask>();
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
            TimeoutException('等待状态 $status 超时（task=$taskId）'));
      }
    });
    void check() {
      final latest = _latest[taskId];
      if (latest != null && latest.status == status) {
        if (!completer.isCompleted) completer.complete(latest);
      }
    }

    void registerWaiter() {
      if (completer.isCompleted) return;
      final waiter = Completer<void>();
      _waiters.add(waiter);
      waiter.future.then((_) {
        if (completer.isCompleted) return;
        check();
        // 每个新事件都会重新唤醒并再次检查，直到命中目标状态。
        registerWaiter();
      });
    }

    check();
    registerWaiter();
    return completer.future.then((task) {
      timer.cancel();
      return task;
    });
  }

  void close() {
    _subscription.cancel();
  }
}

/// 等待条件成立（轮询）。
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String description = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('waitUntil 超时：$description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// 临时目录测试基座。
class TestStorage {
  TestStorage._(this.root);

  final Directory root;

  static Future<TestStorage> create() async {
    final dir = await Directory.systemTemp.createTemp('mfuns_download_test_');
    return TestStorage._(dir);
  }

  DownloadStorage storage() => DownloadStorage(rootProvider: () async => root);

  Future<void> cleanup() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  }
}
