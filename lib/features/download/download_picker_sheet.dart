import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/download/download_manager.dart';
import '../../core/download/download_status.dart';
import '../../core/download/download_task.dart';
import '../../core/download/download_transport.dart';
import '../home/home_repository.dart';
import 'download_page.dart';
import 'widgets/download_progress.dart';

/// 下载选择弹窗：业务单位是一个视频。
///
/// - 选择清晰度，并勾选要下载的分P（默认全部）；
/// - 已存在于任务中的分P按状态锁定显示（已完成 ✓ / 下载中 / 失败等），
///   任务外的分P可自由勾选（补下）。
/// - 显示预计大小（服务端支持 Content-Length / Range 时准确）。
class DownloadPickerSheet extends StatefulWidget {
  const DownloadPickerSheet({
    super.key,
    required this.videoId,
    required this.title,
    required this.cover,
    required this.qualities,
    this.selectedQuality,
    this.manager,
  });

  final int videoId;
  final String title;
  final String cover;

  /// 全部分P的全部清晰度（同一清晰度在各分P有独立直链）。
  final List<VideoQuality> qualities;

  /// 当前播放的清晰度（默认选中）。
  final VideoQuality? selectedQuality;
  final DownloadManager? manager;

  @override
  State<DownloadPickerSheet> createState() => _DownloadPickerSheetState();

  /// 从视频详情页打开下载选择弹窗。
  static Future<void> show(
    BuildContext context, {
    required int videoId,
    required String title,
    required String cover,
    required List<VideoQuality> qualities,
    VideoQuality? selectedQuality,
    DownloadManager? manager,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DownloadPickerSheet(
        videoId: videoId,
        title: title,
        cover: cover,
        qualities: qualities,
        selectedQuality: selectedQuality,
        manager: manager,
      ),
    );
  }
}

class _DownloadPickerSheetState extends State<DownloadPickerSheet> {
  late final DownloadManager _manager;
  late String _qualityKey;
  VideoQuality? _quality;
  int? _probeSize;
  var _probing = false;
  var _creating = false;
  DownloadTask? _task;
  String? _notice;
  StreamSubscription<List<DownloadTask>>? _subscription;

  /// 勾选的分P（默认全部）。
  late Set<int> _selectedParts;

  @override
  void initState() {
    super.initState();
    _manager = widget.manager ?? DownloadManager.instance;
    final initial = widget.selectedQuality ?? widget.qualities.first;
    _quality = initial;
    _qualityKey = _keyOf(initial);
    _selectedParts = {..._allParts};
    _subscription = _manager.watchTasks().listen(_onTasks);
    _refreshTask();
    _probe();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String _keyOf(VideoQuality quality) =>
      DownloadTask.normalizeQualityKey(_labelOf(quality));

  String _labelOf(VideoQuality quality) {
    final source = '${quality.name} ${quality.label}';
    final match = RegExp(r'(?<!\d)(\d{3,4})\s*[pP]?(?!\d)').firstMatch(source);
    if (match != null) return '${match.group(1)}p';
    if (quality.name.isNotEmpty) return quality.name;
    if (quality.label.isNotEmpty) return quality.label;
    return 'default';
  }

  /// 全部分P序号（升序）。
  List<int> get _allParts =>
      widget.qualities.map((q) => q.part).toSet().toList()..sort();

  /// 当前清晰度在指定分P的直链。
  VideoQuality? _qualityForPart(int part) {
    final choices = widget.qualities
        .where((q) => _keyOf(q) == _qualityKey && q.part == part)
        .toList();
    return choices.isEmpty ? null : choices.first;
  }

  /// 任务内指定分P的明细（不存在返回 null）。
  DownloadPartTask? _taskPartOf(int part) {
    final task = _task;
    if (task == null) return null;
    for (final item in task.parts) {
      if (item.part == part) return item;
    }
    return null;
  }

  /// 勾选中、且不在现有任务中的分P数（可新增下载的分P）。
  int get _newlySelectedCount => _selectedParts
      .where((part) => _taskPartOf(part) == null)
      .length;

  /// 勾选的分P数。
  int get _selectedPartCount => _selectedParts.length;

  /// 构造下载请求：只包含勾选的分P直链；
  /// 已存在于任务中的分P不重复请求（由任务合并逻辑处理）。
  DownloadRequest get _request {
    final parts = (_selectedParts.toList()..sort())
        .where((part) => _taskPartOf(part) == null)
        .toList();
    return DownloadRequest(
      videoId: widget.videoId,
      title: widget.title,
      cover: widget.cover,
      quality: _qualityKey,
      qualityLabel: _labelOf(_quality ?? widget.qualities.first),
      parts: [
        for (final part in parts)
          if (_qualityForPart(part) != null)
            DownloadPartSource(part: part, url: _qualityForPart(part)!.url),
      ],
    );
  }

  Future<void> _onTasks(List<DownloadTask> tasks) async {
    if (!mounted) return;
    await _refreshTask();
    if (mounted) setState(() {});
  }

  Future<void> _refreshTask() async {
    _task = await _manager.findTask(
      videoId: widget.videoId,
      quality: _qualityKey,
    );
  }

  void _selectQuality(VideoQuality quality) {
    setState(() {
      _quality = quality;
      _qualityKey = _keyOf(quality);
      _selectedParts = {..._allParts};
    });
    _refreshTask();
    _probe();
  }

  void _togglePart(int part, bool selected) {
    setState(() {
      if (selected) {
        _selectedParts.add(part);
      } else {
        _selectedParts.remove(part);
      }
    });
    _probe();
  }

  Future<void> _probe() async {
    if (_probing) return;
    setState(() {
      _probing = true;
      _probeSize = null;
    });
    final size = await _manager.probeVideoSize(_request);
    if (!mounted) return;
    setState(() {
      _probing = false;
      _probeSize = size;
    });
  }

  Future<void> _submit({bool force = false}) async {
    if (_creating) return;
    final task = _task;
    final newCount = _newlySelectedCount;
    if (task != null) {
      if (task.status.isActive) {
        // 已在下载队列中。
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('该清晰度已在下载队列中')));
        return;
      }
      if (task.status == DownloadStatus.completed && newCount == 0) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('该清晰度已下载完成')));
        return;
      }
      if (task.status == DownloadStatus.paused && newCount == 0) {
        await _manager.resume(task.taskId);
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }
      if ((task.status == DownloadStatus.failed ||
              task.status == DownloadStatus.canceled) &&
          newCount == 0) {
        await _manager.retry(task.taskId);
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }
      // 勾选了任务外的新分P：走 enqueue 合并追加。
    }
    setState(() => _creating = true);
    try {
      await _manager.enqueue(_request, force: force);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已加入下载队列')));
    } on DownloadException catch (error) {
      if (!mounted) return;
      if (error.kind == DownloadErrorKind.network &&
          !force &&
          _manager.policy.wifiOnly) {
        // 移动网络下主动开始下载：明确提示后让用户决定。
        final proceed = await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          builder: (dialogContext) => AlertDialog(
            title: const Text('使用移动网络下载？'),
            content: const Text(
              '当前连接的是移动网络，且已开启“仅 Wi-Fi 下载”。'
              '继续下载将消耗手机流量，是否继续？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('仍然下载'),
              ),
            ],
          ),
        );
        if (proceed == true && mounted) {
          await _submit(force: true);
        }
        return;
      }
      setState(() => _notice = error.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String get _buttonLabel {
    final task = _task;
    final newCount = _newlySelectedCount;
    if (task == null) return '下载选中的 $_selectedPartCount 个分P';
    switch (task.status) {
      case DownloadStatus.completed:
        return newCount > 0 ? '补下选中的 $newCount 个分P' : '已下载，前往下载管理';
      case DownloadStatus.downloading:
      case DownloadStatus.pending:
        return '已在下载队列中';
      case DownloadStatus.paused:
        return newCount > 0 ? '下载选中的 $newCount 个分P' : '继续下载';
      case DownloadStatus.failed:
      case DownloadStatus.canceled:
        return newCount > 0 ? '下载选中的 $newCount 个分P' : '重新下载';
    }
  }

  /// 任务内分P的状态标签。
  String _partStatusLabel(DownloadPartTask part) => switch (part.status) {
        DownloadStatus.completed => 'P${part.part} ✓',
        DownloadStatus.downloading =>
          'P${part.part} ${(part.progress * 100).round()}%',
        DownloadStatus.paused => 'P${part.part} 已暂停',
        DownloadStatus.failed => 'P${part.part} 失败',
        DownloadStatus.canceled => 'P${part.part} 已取消',
        DownloadStatus.pending => 'P${part.part} 排队中',
      };

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    final qualities = widget.qualities
        .map((q) => (_keyOf(q), q))
        .fold<Map<String, VideoQuality>>(<String, VideoQuality>{},
            (map, entry) {
          map.putIfAbsent(entry.$1, () => entry.$2);
          return map;
        })
        .values
        .toList(growable: false);
    final sizeText = _probing
        ? '正在获取大小…'
        : _probeSize != null
            ? '约 ${formatBytes(_probeSize!)}'
            : '大小未知（服务端未提供）';
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Icon(Icons.download_rounded, color: palette.primary),
                const SizedBox(width: 8),
                const Text('下载视频',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const DownloadPage()),
                  ),
                  child: const Text('下载管理'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('清晰度',
                style: TextStyle(
                    color: palette.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: qualities
                  .map((quality) => ChoiceChip(
                        label: Text(_labelOf(quality)),
                        selected: _keyOf(quality) == _qualityKey,
                        onSelected: _keyOf(quality) == _qualityKey
                            ? null
                            : (_) => _selectQuality(quality),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('选择分P',
                    style: TextStyle(
                        color: palette.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                if (_task == null && _allParts.length > 1)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => setState(() {
                      if (_selectedParts.length == _allParts.length) {
                        _selectedParts.clear();
                      } else {
                        _selectedParts = {..._allParts};
                      }
                    }),
                    child: Text(_selectedParts.length == _allParts.length
                        ? '全不选'
                        : '全选'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allParts.map((part) {
                final taskPart = _taskPartOf(part);
                if (taskPart != null) {
                  // 已存在于任务中：按状态锁定显示。
                  return Chip(
                    label: Text(_partStatusLabel(taskPart)),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: taskPart.isPlayable
                          ? const Color(0xFF4FA36C)
                          : palette.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide.none,
                    backgroundColor: taskPart.isPlayable
                        ? const Color(0xFF4FA36C).withOpacity(.1)
                        : palette.surfaceContainerHighest,
                  );
                }
                final selected = _selectedParts.contains(part);
                return FilterChip(
                  label: Text('P$part'),
                  selected: selected,
                  onSelected: (value) => _togglePart(part, value),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.straighten_rounded,
                    size: 16, color: palette.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '预计大小：$sizeText',
                  style: TextStyle(
                    color: palette.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if (_notice != null) ...[
              const SizedBox(height: 8),
              Text(
                _notice!,
                style: TextStyle(color: palette.error, fontSize: 13),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _creating ? null : _submit,
                icon: _creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(_buttonLabel),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
