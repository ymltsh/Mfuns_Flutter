import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/download/download_task.dart';
import '../../core/theme/app_theme.dart';
import '../content/export/article_exporter.dart' show ExportResult;
import 'download_controller.dart';
import 'local_video_player.dart';
import 'video_exporter.dart';
import 'widgets/download_progress.dart';
import 'widgets/download_task_card.dart';

/// 下载管理页：下载中 / 已下载 两个标签，顶部统计与批量清理。
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key, DownloadController? controller})
      : _controller = controller;

  final DownloadController? _controller;

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage>
    with SingleTickerProviderStateMixin {
  late final DownloadController _controller;
  late final TabController _tabController;
  var _selectionMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _controller = widget._controller ?? DownloadController();
    _controller.initialize();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    if (widget._controller == null) _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      _selected.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final confirmed = await _confirmDelete(_selected.length);
    if (confirmed != true || !mounted) return;
    await _controller.deleteMany(_selected.toList());
    if (mounted) {
      setState(() {
        _selectionMode = false;
        _selected.clear();
      });
    }
  }

  Future<bool?> _confirmDelete([int count = 1]) => showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(count > 1 ? '删除 $count 个下载' : '删除下载'),
          content: Text(
              count > 1 ? '将删除这些下载任务与本地文件，确定删除吗？' : '将删除该下载任务与本地文件，确定删除吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        ),
      );

  void _play(DownloadTask task) {
    if (!task.isPlayable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地文件不存在，请重新下载')),
      );
      return;
    }
    // 收集已完成分P → 本地播放器内可像在线播放一样切换分P。
    final parts = <int, String>{
      for (final part in task.parts)
        if (part.isPlayable && part.filePath.isNotEmpty)
          part.part: part.filePath,
    };
    if (parts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地文件不存在，请重新下载')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LocalVideoPlayer(
        title: task.title,
        parts: parts,
        initialPart: parts.keys.first,
      ),
    ));
  }

  /// 导出视频：选择分P → 保存到系统公共目录 → 打开分享面板。
  Future<void> _export(DownloadTask task) async {
    final playableParts = task.parts
        .where((part) => part.isPlayable && part.filePath.isNotEmpty)
        .toList(growable: false);
    if (playableParts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可导出的分P，请重新下载')),
      );
      return;
    }
    final selected = await showModalBottomSheet<Set<int>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExportPartPickerSheet(
        title: task.title,
        parts: playableParts,
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    final items = <VideoExportItem>[
      for (final part in task.parts)
        if (selected.contains(part.part) &&
            part.isPlayable &&
            part.filePath.isNotEmpty)
          VideoExportItem(
            part: part.part,
            sourcePath: part.filePath,
            title: task.title,
            qualityLabel: task.qualityLabel,
          ),
    ];
    await _runVideoExport(items);
  }

  Future<void> _runVideoExport(List<VideoExportItem> items) async {
    final progress = ValueNotifier<String>('');
    var dialogOpen = true;
    final dialogFuture = showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => _ExportProgressDialog(
        message: '正在导出视频…',
        progress: progress,
      ),
    );
    dialogFuture.whenComplete(() => dialogOpen = false);
    List<ExportResult>? results;
    String? errorNotice;
    try {
      final exported = await VideoExporter.persist(items,
          onProgress: (message) => progress.value = message);
      if (exported.isEmpty) {
        errorNotice = '导出失败，请稍后重试';
      } else {
        results = exported;
      }
    } on Exception catch (error) {
      errorNotice = '导出失败：$error';
    } finally {
      if (mounted && dialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
    }
    if (!mounted) return;
    if (errorNotice != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorNotice)));
      return;
    }
    final completed = results;
    if (completed == null || completed.isEmpty) return;
    try {
      await VideoExporter.share(completed);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已导出视频')));
      }
    } on Exception {
      // 分享面板不可用（如旧版 Windows / 测试环境）：提示文件位置。
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已保存到本地：${completed.first.path}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('下载管理', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          if (_selectionMode)
            TextButton(
              onPressed: _deleteSelected,
              child: Text(
                '删除所选（${_selected.length}）',
                style: TextStyle(color: palette.error),
              ),
            )
          else
            TextButton(
              onPressed: _toggleSelectionMode,
              child: const Text('批量清理'),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          children: [
            _StatsHeader(
              count: _controller.completedCount,
              usedSpace: _controller.usedSpaceBytes,
            ),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: '下载中（${_controller.activeTasks.length}）'),
                Tab(text: '已下载（${_controller.completedCount}）'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildList(
                    tasks: _controller.activeTasks,
                    emptyText: '暂无下载任务\n从视频详情页点击“下载”开始缓存视频',
                  ),
                  _buildList(
                    tasks: _controller.completedTasks,
                    emptyText: '暂无已下载视频',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList({
    required List<DownloadTask> tasks,
    required String emptyText,
  }) {
    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            emptyText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final task = tasks[index];
        final selected = _selected.contains(task.taskId);
        return InkWell(
          onLongPress: _selectionMode
              ? null
              : () {
                  setState(() {
                    _selectionMode = true;
                    _selected.add(task.taskId);
                  });
                },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: _selectionMode && selected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary, width: 2)
                  : null,
            ),
            child: Stack(
              children: [
                DownloadTaskCard(
                  task: task,
                  onPause: () => _controller.pause(task.taskId),
                  onResume: () => _controller.resume(task.taskId),
                  onRetry: () => _controller.retry(task.taskId),
                  onCancel: () => _controller.cancel(task.taskId),
                  onDelete: () async {
                    final confirmed = await _confirmDelete();
                    if (confirmed == true) {
                      await _controller.delete(task.taskId);
                    }
                  },
                  onPlay: () => _play(task),
                  onExport: () => _export(task),
                ),
                if (_selectionMode)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() {
                        if (!_selected.add(task.taskId)) {
                          _selected.remove(task.taskId);
                        }
                      }),
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.count, required this.usedSpace});

  final int count;
  final int usedSpace;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.primary.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_open_rounded, color: palette.primary, size: 20),
          const SizedBox(width: 10),
          Text(
            '已下载 $count 个视频',
            style: TextStyle(
              color: palette.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            '占用 ${formatBytes(usedSpace)}',
            style: TextStyle(color: palette.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// 导出分P选择弹窗：多选要导出的已完成分P，确认后返回勾选集合。
class _ExportPartPickerSheet extends StatefulWidget {
  const _ExportPartPickerSheet({required this.title, required this.parts});

  final String title;
  final List<DownloadPartTask> parts;

  @override
  State<_ExportPartPickerSheet> createState() => _ExportPartPickerSheetState();
}

class _ExportPartPickerSheetState extends State<_ExportPartPickerSheet> {
  late final Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {for (final part in widget.parts) part.part};
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.ios_share_rounded, color: palette.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '导出视频',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => setState(() {
                    if (_selected.length == widget.parts.length) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll(widget.parts.map((part) => part.part));
                    }
                  }),
                  child: Text(
                      _selected.length == widget.parts.length ? '全不选' : '全选'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '选择要导出的分P，将保存到系统视频目录并打开分享面板',
              style: TextStyle(color: palette.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.parts.map((part) {
                final selected = _selected.contains(part.part);
                return FilterChip(
                  label: Text('P${part.part}'),
                  selected: selected,
                  onSelected: (value) => setState(() {
                    if (value) {
                      _selected.add(part.part);
                    } else {
                      _selected.remove(part.part);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop({..._selected}),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(_selected.isEmpty
                    ? '请选择分P'
                    : '导出选中的 ${_selected.length} 个分P'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 导出进度对话框：展示当前进度，阻止系统返回与误触关闭。
class _ExportProgressDialog extends StatelessWidget {
  const _ExportProgressDialog({
    required this.message,
    required this.progress,
  });

  final String message;
  final ValueListenable<String> progress;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: progress,
                builder: (context, value, _) => Text(
                  value.isEmpty ? message : value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppPalette.of(context).muted,
                      fontSize: 13,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
}
