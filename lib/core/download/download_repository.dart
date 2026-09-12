import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'download_status.dart';
import 'download_storage.dart';
import 'download_task.dart';

/// 下载任务持久化存储抽象：生产实现使用 SQLite，测试使用内存实现。
abstract class DownloadTaskStore {
  Future<void> init();

  Future<void> upsert(DownloadTask task);

  Future<void> delete(String taskId);

  Future<DownloadTask?> get(String taskId);

  Future<List<DownloadTask>> getAll();

  Future<void> close();
}

/// Windows/Linux 下载任务存储。
///
/// `sqflite` 在这两个桌面平台没有实现，因此把体积很小的任务元数据保存为
/// JSON；视频文件仍由 [DownloadStorage] 独立管理。写入通过队列串行化，避免
/// 多个并发下载同时上报进度时互相覆盖文件。
class FileDownloadTaskStore implements DownloadTaskStore {
  FileDownloadTaskStore({Future<File> Function()? fileProvider})
      : _fileProvider = fileProvider ?? _defaultFileProvider;

  final Future<File> Function() _fileProvider;
  final Map<String, DownloadTask> _tasks = {};
  Future<void> _writeTail = Future<void>.value();
  var _initialized = false;

  static Future<File> _defaultFileProvider() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'mfuns_downloads.json'));
  }

  @override
  Future<void> init() async {
    if (_initialized) return;
    final file = await _fileProvider();
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final value in decoded.whereType<Map<String, dynamic>>()) {
            final task = DownloadTask.fromMap(value);
            if (task.taskId.isNotEmpty) _tasks[task.taskId] = task;
          }
        }
      }
    } on FileSystemException {
      // 文件不可读时保留空列表，后续写入会重新建立存储。
    } on FormatException {
      // 损坏的元数据不能阻断应用启动或新下载。
    }
    _initialized = true;
  }

  @override
  Future<void> upsert(DownloadTask task) async {
    await init();
    _tasks[task.taskId] = task;
    await _persist();
  }

  @override
  Future<void> delete(String taskId) async {
    await init();
    _tasks.remove(taskId);
    await _persist();
  }

  @override
  Future<DownloadTask?> get(String taskId) async {
    await init();
    return _tasks[taskId];
  }

  @override
  Future<List<DownloadTask>> getAll() async {
    await init();
    return _tasks.values.toList(growable: false);
  }

  Future<void> _persist() {
    final snapshot =
        _tasks.values.map((task) => task.toJson()).toList(growable: false);
    final write = _writeTail.then((_) async {
      final file = await _fileProvider();
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(snapshot), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    });
    _writeTail = write.then<void>((_) {}, onError: (_) {});
    return write;
  }

  @override
  Future<void> close() async {
    await _writeTail;
  }
}

/// SQLite 实现：`download_tasks` 表（任务 = 视频，分P明细存 parts_json）。
class SqfliteDownloadTaskStore implements DownloadTaskStore {
  SqfliteDownloadTaskStore({String? databasePath})
      : _databasePath = databasePath;

  static const _dbName = 'mfuns_downloads.db';
  static const _table = 'download_tasks';

  final String? _databasePath;
  Database? _db;

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    final path = _databasePath ?? '${await getDatabasesPath()}/$_dbName';
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            task_id TEXT PRIMARY KEY,
            video_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            cover TEXT NOT NULL DEFAULT '',
            quality TEXT NOT NULL,
            quality_label TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL,
            downloaded_bytes INTEGER NOT NULL DEFAULT 0,
            total_bytes INTEGER NOT NULL DEFAULT 0,
            error_message TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            parts_json TEXT NOT NULL DEFAULT '[]'
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_download_tasks_video ON $_table (video_id, quality)');
      },
      // 开发期表结构变更（任务粒度从分P升级为视频）：
      // 旧表直接重建，不存在需保留的历史数据。
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.execute('DROP TABLE IF EXISTS $_table');
        await db.execute('''
          CREATE TABLE $_table (
            task_id TEXT PRIMARY KEY,
            video_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            cover TEXT NOT NULL DEFAULT '',
            quality TEXT NOT NULL,
            quality_label TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL,
            downloaded_bytes INTEGER NOT NULL DEFAULT 0,
            total_bytes INTEGER NOT NULL DEFAULT 0,
            error_message TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            parts_json TEXT NOT NULL DEFAULT '[]'
          )
        ''');
        await db.execute(
            'CREATE INDEX idx_download_tasks_video ON $_table (video_id, quality)');
      },
    );
    _db = db;
    return db;
  }

  @override
  Future<void> init() async {
    await _open();
  }

  @override
  Future<void> upsert(DownloadTask task) async {
    final db = await _open();
    await db.insert(
      _table,
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> delete(String taskId) async {
    final db = await _open();
    await db.delete(_table, where: 'task_id = ?', whereArgs: [taskId]);
  }

  @override
  Future<DownloadTask?> get(String taskId) async {
    final db = await _open();
    final rows = await db.query(
      _table,
      where: 'task_id = ?',
      whereArgs: [taskId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DownloadTask.fromMap(rows.first);
  }

  @override
  Future<List<DownloadTask>> getAll() async {
    final db = await _open();
    final rows = await db.query(_table, orderBy: 'created_at ASC');
    return rows.map(DownloadTask.fromMap).toList(growable: false);
  }

  @override
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }
}

/// 测试用内存实现：不依赖平台插件。
class InMemoryDownloadTaskStore implements DownloadTaskStore {
  final Map<String, DownloadTask> _tasks = {};

  @override
  Future<void> init() async {}

  @override
  Future<void> upsert(DownloadTask task) async {
    _tasks[task.taskId] = task;
  }

  @override
  Future<void> delete(String taskId) async {
    _tasks.remove(taskId);
  }

  @override
  Future<DownloadTask?> get(String taskId) async => _tasks[taskId];

  @override
  Future<List<DownloadTask>> getAll() async =>
      _tasks.values.toList(growable: false);

  @override
  Future<void> close() async => _tasks.clear();
}

/// 下载任务数据层：内存缓存 + 持久化 + 文件系统协调。
///
/// 任务 = 视频（唯一键 `videoId + quality`），分P明细挂在任务内部。
/// - 启动恢复：completed 校验各分P正式文件（缺失分P补下），
///   进行中/排队态回填分P临时文件字节数，清理无效任务与孤儿文件。
/// - 对外通过 [watchTasks] 流与 ChangeNotifier 双通道通知变化。
class DownloadRepository extends ChangeNotifier {
  DownloadRepository({
    required DownloadTaskStore store,
    required DownloadStorage storage,
  })  : _store = store,
        _storage = storage;

  final DownloadTaskStore _store;
  final DownloadStorage _storage;

  final StreamController<List<DownloadTask>> _controller =
      StreamController<List<DownloadTask>>.broadcast();
  final Map<String, DownloadTask> _tasks = {};
  var _initialized = false;

  bool get isInitialized => _initialized;

  List<DownloadTask> get tasks =>
      List<DownloadTask>.unmodifiable(_tasks.values.toList(growable: false));

  Stream<List<DownloadTask>> watchTasks() => _controller.stream;

  Future<DownloadTask?> task(String taskId) async => _tasks[taskId];

  Future<DownloadTask?> findTask({
    required int videoId,
    required String quality,
  }) async {
    final id = DownloadTask.buildTaskId(videoId: videoId, quality: quality);
    return _tasks[id];
  }

  /// 初始化并恢复：加载数据库 → 校验正式文件 → 回填临时文件字节 →
  /// 清理孤儿文件。
  Future<void> initialize() async {
    await _store.init();
    final stored = await _store.getAll();
    final restored = <DownloadTask>[];
    for (final item in stored) {
      final task = await _restoreTask(item);
      if (task != null) restored.add(task);
    }
    _tasks
      ..clear()
      ..addEntries(restored.map((task) => MapEntry(task.taskId, task)));
    await _storage.removeOrphanFiles(restored);
    _initialized = true;
    _emit();
  }

  /// 单任务恢复规则；返回 null 表示任务已被清理（无效记录）。
  Future<DownloadTask?> _restoreTask(DownloadTask task) async {
    if (task.parts.isEmpty) {
      // 无分P明细的残留记录：直接清理。
      await _storage.deleteVideoDirectory(task.videoId);
      await _store.delete(task.taskId);
      return null;
    }
    var parts = task.parts;
    if (task.status == DownloadStatus.completed) {
      var hasAnyFile = false;
      var missingAny = false;
      final checked = <DownloadPartTask>[];
      for (final part in parts) {
        if (await _storage.verifyCompletedFile(part)) {
          hasAnyFile = true;
          checked.add(part);
        } else {
          missingAny = true;
          // 正式文件缺失/损坏：该分P回到排队态等待补下。
          checked.add(part.copyWith(
            status: DownloadStatus.pending,
            downloadedBytes: 0,
            totalBytes: 0,
            errorMessage: '',
          ));
        }
      }
      if (!hasAnyFile) {
        // 全部文件都不存在：清理无效记录与残留文件。
        await _storage.deleteVideoDirectory(task.videoId);
        await _store.delete(task.taskId);
        return null;
      }
      final restored = task.copyWith(
        parts: checked,
        status: missingAny ? DownloadStatus.pending : task.status,
        errorMessage: '',
        updatedAt: DateTime.now(),
      );
      await _store.upsert(restored);
      return restored;
    }
    if (task.status == DownloadStatus.pending ||
        task.status == DownloadStatus.downloading) {
      // 检查各分P .part 文件，回填断点字节数后回到排队态等待恢复下载。
      final checked = <DownloadPartTask>[];
      for (final part in parts) {
        if (part.isPlayable) {
          checked.add(part);
          continue;
        }
        var bytes = 0;
        try {
          final tempFile = File(part.tempFilePath);
          if (await tempFile.exists()) {
            bytes = await tempFile.length();
          }
        } catch (_) {
          bytes = 0;
        }
        checked.add(part.copyWith(
          downloadedBytes: bytes,
          status: DownloadStatus.pending,
          errorMessage: '',
        ));
      }
      final restored = task.copyWith(
        parts: checked,
        downloadedBytes: _sumDownloaded(checked),
        totalBytes: _sumTotal(checked),
        status: DownloadStatus.pending,
        errorMessage: '',
        updatedAt: DateTime.now(),
      );
      await _store.upsert(restored);
      return restored;
    }
    // paused / failed / canceled：保持原状。
    return task;
  }

  int _sumDownloaded(List<DownloadPartTask> parts) =>
      parts.fold<int>(0, (sum, part) => sum + part.downloadedBytes);

  int _sumTotal(List<DownloadPartTask> parts) =>
      parts.fold<int>(0, (sum, part) => sum + part.totalBytes);

  /// 创建下载任务（一个视频 + 一个清晰度）；相同 `videoId + quality`
  /// 的任务不会重复创建：
  /// - 已存在任务且请求不含新分P：按任务状态返回（进行中/完成/暂停直接
  ///   返回，失败/取消重置为排队态）。
  /// - 已存在任务但请求含新分P：把新分P追加进任务（补下），任务回到
  ///   排队态由管理器统一调度。
  Future<DownloadTask> createTask(DownloadRequest request) async {
    final existing = await findTask(
      videoId: request.videoId,
      quality: request.quality,
    );
    if (existing != null) {
      final existingParts = existing.parts.map((p) => p.part).toSet();
      final additions = request.parts
          .where((source) => !existingParts.contains(source.part))
          .toList(growable: false);
      if (additions.isEmpty) {
        if (existing.status.isActive ||
            existing.status == DownloadStatus.paused ||
            existing.status == DownloadStatus.completed) {
          return existing;
        }
        // failed/canceled：重置为排队态，未完成分P重新排队。
        final resetParts = existing.parts
            .map((part) => part.copyWith(
                  status: part.isPlayable
                      ? DownloadStatus.completed
                      : DownloadStatus.pending,
                  errorMessage: '',
                ))
            .toList(growable: false);
        final reset = existing.copyWith(
          status: DownloadStatus.pending,
          errorMessage: '',
          downloadedBytes: _sumDownloaded(resetParts),
          totalBytes: _sumTotal(resetParts),
          updatedAt: DateTime.now(),
          parts: resetParts,
        );
        await _upsert(reset);
        return reset;
      }
      // 追加新分P（补下）：任务回到排队态，已完成分P保留。
      final newParts = <DownloadPartTask>[];
      for (final source in additions) {
        final placeholder = DownloadPartTask(
          part: source.part,
          sourceUrl: source.url,
          filePath: '',
          tempFilePath: '',
          downloadedBytes: 0,
          totalBytes: 0,
          status: DownloadStatus.pending,
        );
        final filePath = await _storage.filePathFor(
          request.videoId,
          source.part,
          request.quality,
          source.url,
        );
        final tempFilePath = await _storage.tempFilePathFor(
          request.videoId,
          source.part,
          request.quality,
          source.url,
        );
        newParts.add(placeholder.copyWith(
          filePath: filePath,
          tempFilePath: tempFilePath,
        ));
      }
      final mergedParts = [...existing.parts, ...newParts]
        ..sort((a, b) => a.part.compareTo(b.part));
      final merged = existing.copyWith(
        status: DownloadStatus.pending,
        errorMessage: '',
        downloadedBytes: _sumDownloaded(mergedParts),
        totalBytes: _sumTotal(mergedParts),
        updatedAt: DateTime.now(),
        parts: mergedParts,
      );
      await _upsert(merged);
      return merged;
    }
    final now = DateTime.now();
    final parts = <DownloadPartTask>[];
    for (final source in request.parts) {
      final placeholder = DownloadPartTask(
        part: source.part,
        sourceUrl: source.url,
        filePath: '',
        tempFilePath: '',
        downloadedBytes: 0,
        totalBytes: 0,
        status: DownloadStatus.pending,
      );
      final filePath = await _storage.filePathFor(
        request.videoId,
        source.part,
        request.quality,
        source.url,
      );
      final tempFilePath = await _storage.tempFilePathFor(
        request.videoId,
        source.part,
        request.quality,
        source.url,
      );
      parts.add(placeholder.copyWith(
        filePath: filePath,
        tempFilePath: tempFilePath,
      ));
    }
    final task = DownloadTask(
      taskId: request.taskId,
      videoId: request.videoId,
      title: request.title,
      cover: request.cover,
      quality: request.quality,
      qualityLabel: request.qualityLabel,
      status: DownloadStatus.pending,
      downloadedBytes: 0,
      totalBytes: 0,
      createdAt: now,
      updatedAt: now,
      parts: parts,
    );
    await _upsert(task);
    return task;
  }

  /// 更新任务的分P明细（不改变任务状态），并重算汇总进度。
  Future<void> updateParts(
    String taskId,
    List<DownloadPartTask> parts,
  ) async {
    final task = _tasks[taskId];
    if (task == null) return;
    await _upsert(task.copyWith(
      parts: parts,
      downloadedBytes: _sumDownloaded(parts),
      totalBytes: _sumTotal(parts),
      updatedAt: DateTime.now(),
    ));
  }

  /// 用重新获取的播放地址替换任务内对应分P的短期签名 URL。
  Future<bool> updatePartSources(
    String taskId,
    List<DownloadPartSource> sources,
  ) async {
    final task = _tasks[taskId];
    if (task == null || sources.isEmpty) return false;
    final byPart = {for (final source in sources) source.part: source.url};
    var changed = false;
    final parts = task.parts.map((part) {
      final url = byPart[part.part];
      if (url == null || url.isEmpty || url == part.sourceUrl) return part;
      changed = true;
      return part.copyWith(sourceUrl: url);
    }).toList(growable: false);
    if (changed) await updateParts(taskId, parts);
    return changed;
  }

  /// 更新单个分P进度并汇总到任务。
  Future<void> updatePartProgress(
    DownloadTask task,
    int part, {
    required int downloadedBytes,
    required int totalBytes,
    double speed = 0,
  }) async {
    final updatedParts = _mapPart(
        task,
        part,
        (item) => item.copyWith(
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes,
            ));
    await _upsert(task.copyWith(
      parts: updatedParts,
      downloadedBytes: _sumDownloaded(updatedParts),
      totalBytes: _sumTotal(updatedParts),
      speedBytesPerSecond: speed,
      updatedAt: DateTime.now(),
    ));
  }

  /// 更新任务级状态（错误信息等）。
  Future<void> setTaskStatus(
    DownloadTask task,
    DownloadStatus status, {
    String errorMessage = '',
  }) =>
      _upsert(task.copyWith(
        status: status,
        errorMessage: errorMessage,
        updatedAt: DateTime.now(),
      ));

  /// 更新单个分P状态。
  Future<void> setPartStatus(
    DownloadTask task,
    int part,
    DownloadStatus status, {
    String errorMessage = '',
  }) async {
    final updatedParts = _mapPart(
        task,
        part,
        (item) => item.copyWith(
              status: status,
              errorMessage: errorMessage,
            ));
    await _upsert(task.copyWith(
      parts: updatedParts,
      updatedAt: DateTime.now(),
    ));
  }

  /// 分P下载完成：校验并重命名 `.part` 为正式文件，标记该分P completed；
  /// 全部分P完成后任务自动 completed。
  Future<DownloadTask?> completePart(DownloadTask task, int part) async {
    final current = _tasks[task.taskId] ?? task;
    final target = current.parts.where((p) => p.part == part).firstOrNull;
    if (target == null) return null;
    await _storage.completeFile(target);
    var completedParts = current.parts
        .map((p) =>
            p.part == part ? p.copyWith(status: DownloadStatus.completed) : p)
        .toList(growable: false);
    // 重命名后再以实际文件大小校准（总大小未知的场景）。
    var allDone = completedParts.every((p) => p.isPlayable);
    var totalBytes = _sumTotal(completedParts);
    if (allDone) {
      final calibrated = <DownloadPartTask>[];
      for (final p in completedParts) {
        var size = p.downloadedBytes;
        try {
          final file = File(p.filePath);
          if (await file.exists()) size = await file.length();
        } catch (_) {}
        calibrated.add(p.copyWith(downloadedBytes: size, totalBytes: size));
      }
      totalBytes = _sumTotal(calibrated);
      completedParts = calibrated;
    }
    final updated = current.copyWith(
      parts: completedParts,
      downloadedBytes: _sumDownloaded(completedParts),
      totalBytes: totalBytes,
      status: allDone ? DownloadStatus.completed : current.status,
      speedBytesPerSecond: 0,
      errorMessage: '',
      updatedAt: DateTime.now(),
    );
    await _upsert(updated);
    return updated;
  }

  /// 删除任务：移除数据库记录 + 全部分P本地文件（正式与临时）。
  Future<void> deleteTask(String taskId) async {
    final task = _tasks[taskId];
    if (task != null) {
      for (final part in task.parts) {
        await _storage.deletePartFiles(part);
      }
      await _storage.deleteVideoDirectory(task.videoId);
    }
    _tasks.remove(taskId);
    await _store.delete(taskId);
    _emit();
    notifyListeners();
  }

  /// 查询可离线播放的本地文件：
  /// 返回与 `videoId + part + quality` 精确匹配且已通过校验的正式文件路径。
  Future<String?> localFileFor({
    required int videoId,
    required int part,
    required String quality,
  }) async {
    final task = await findTask(videoId: videoId, quality: quality);
    if (task == null) return null;
    final target = task.parts.where((p) => p.part == part).firstOrNull;
    if (target == null || !target.isPlayable) return null;
    if (!await _storage.verifyCompletedFile(target)) return null;
    return target.filePath;
  }

  Future<int> usedSpaceBytes() => _storage.usedSpaceBytes();

  List<DownloadPartTask> _mapPart(
    DownloadTask task,
    int part,
    DownloadPartTask Function(DownloadPartTask item) transform,
  ) {
    return task.parts
        .map((item) => item.part == part ? transform(item) : item)
        .toList(growable: false);
  }

  Future<void> _upsert(DownloadTask task) async {
    _tasks[task.taskId] = task;
    await _store.upsert(task);
    _emit();
    notifyListeners();
  }

  void _emit() {
    // 存储销毁（App 退出）后仍有下载任务在收尾时，忽略后续事件。
    if (_controller.isClosed) return;
    _controller.add(
      List<DownloadTask>.unmodifiable(
        _tasks.values.toList(growable: false)
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      ),
    );
  }

  Future<void> disposeStore() async {
    await _controller.close();
    await _store.close();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
