import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/download/download_manager.dart';
import '../../core/download/download_status.dart';
import '../../core/download/download_task.dart';

/// 下载管理页控制器：订阅 [DownloadManager] 任务流并维护空间统计。
class DownloadController extends ChangeNotifier {
  DownloadController({DownloadManager? manager})
      : _manager = manager ?? DownloadManager.instance;

  final DownloadManager _manager;
  StreamSubscription<List<DownloadTask>>? _subscription;
  List<DownloadTask> _tasks = const [];
  var _usedSpaceBytes = 0;
  var _initialized = false;

  List<DownloadTask> get tasks => _tasks;

  /// 未完成任务（下载中/排队/暂停/失败/取消）。
  List<DownloadTask> get activeTasks => _tasks
      .where((task) => !task.status.isTerminal)
      .toList(growable: false);

  /// 已完成任务。
  List<DownloadTask> get completedTasks =>
      _tasks.where((task) => task.status == DownloadStatus.completed).toList();

  int get usedSpaceBytes => _usedSpaceBytes;

  int get completedCount => completedTasks.length;

  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    _subscription = _manager.watchTasks().listen(_onTasks);
    _tasks = await _manager.getTasks();
    _initialized = true;
    notifyListeners();
    // 空间统计为真实 IO，异步刷新即可，不阻塞任务列表展示。
    unawaited(_refreshSpace());
  }

  void _onTasks(List<DownloadTask> tasks) {
    _tasks = tasks;
    unawaited(_refreshSpace());
    notifyListeners();
  }

  Future<void> _refreshSpace() async {
    _usedSpaceBytes = await _manager.usedSpaceBytes();
  }

  Future<void> pause(String taskId) => _manager.pause(taskId);

  Future<void> resume(String taskId) => _manager.resume(taskId);

  Future<void> retry(String taskId) => _manager.retry(taskId);

  Future<void> cancel(String taskId) => _manager.cancel(taskId);

  Future<void> delete(String taskId) => _manager.delete(taskId);

  /// 批量删除多个任务。
  Future<void> deleteMany(List<String> taskIds) async {
    for (final taskId in taskIds) {
      await _manager.delete(taskId);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
