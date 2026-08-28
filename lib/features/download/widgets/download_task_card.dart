import 'package:flutter/material.dart';

import '../../../core/download/download_status.dart';
import '../../../core/download/download_task.dart';
import 'download_progress.dart';

/// 下载任务卡片：封面、标题、清晰度、分P进度与操作按钮。
///
/// 任务 = 一个视频（含全部分P），卡片展示分P明细与汇总进度。
class DownloadTaskCard extends StatelessWidget {
  const DownloadTaskCard({
    super.key,
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRetry,
    required this.onCancel,
    required this.onDelete,
    required this.onPlay,
    this.onExport,
  });

  final DownloadTask task;

  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onPlay;

  /// 导出已完成视频（仅 completed 任务显示按钮）。
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = task.status;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 92,
                    height: 58,
                    child: task.cover.isEmpty
                        ? ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.videocam_outlined),
                          )
                        : Image.network(
                            task.cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.videocam_outlined),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _Tag(label: task.qualityLabel.isEmpty
                              ? task.quality
                              : task.qualityLabel),
                          const SizedBox(width: 6),
                          _Tag(label: '${task.totalPartCount} 个分P'),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _statusLabel(status, task.errorMessage),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _statusColor(theme, status),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _PartProgressRow(task: task),
            if (status == DownloadStatus.downloading ||
                status == DownloadStatus.pending) ...[
              const SizedBox(height: 8),
              DownloadProgress(
                downloadedBytes: task.downloadedBytes,
                totalBytes: task.totalBytes,
                speedBytesPerSecond: task.speedBytesPerSecond,
              ),
            ],
            if (status == DownloadStatus.paused) ...[
              const SizedBox(height: 8),
              Text(
                '已下载 ${formatBytes(task.downloadedBytes)}，点击继续从断点恢复',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (status == DownloadStatus.failed) ...[
              const SizedBox(height: 8),
              Text(
                task.errorMessage.isEmpty
                    ? '下载失败，请重试'
                    : task.errorMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: _actionButtons(context),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(DownloadStatus status, String errorMessage) =>
      status == DownloadStatus.failed && errorMessage.isNotEmpty
          ? '失败'
          : status.label;

  Color _statusColor(ThemeData theme, DownloadStatus status) =>
      switch (status) {
        DownloadStatus.failed => theme.colorScheme.error,
        DownloadStatus.completed => const Color(0xFF4FA36C),
        DownloadStatus.downloading => theme.colorScheme.primary,
        _ => theme.colorScheme.onSurfaceVariant,
      };

  List<Widget> _actionButtons(BuildContext context) {
    final status = task.status;
    final buttons = <Widget>[];
    void add(IconData icon, String label, VoidCallback onTap) {
      buttons.add(TextButton.icon(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
      ));
    }

    switch (status) {
      case DownloadStatus.downloading:
        add(Icons.pause_rounded, '暂停', onPause);
        add(Icons.close_rounded, '取消', onCancel);
      case DownloadStatus.pending:
        add(Icons.pause_rounded, '暂停', onPause);
        add(Icons.close_rounded, '取消', onCancel);
      case DownloadStatus.paused:
        add(Icons.play_arrow_rounded, '继续', onResume);
        add(Icons.close_rounded, '取消', onCancel);
      case DownloadStatus.failed:
      case DownloadStatus.canceled:
        add(Icons.refresh_rounded, '重试', onRetry);
        add(Icons.delete_outline_rounded, '删除', onDelete);
      case DownloadStatus.completed:
        add(Icons.play_circle_outline_rounded, '播放', onPlay);
        if (onExport != null) {
          add(Icons.ios_share_rounded, '导出', onExport!);
        }
        add(Icons.delete_outline_rounded, '删除', onDelete);
    }
    return buttons;
  }
}

/// 分P进度行：P1 ✓ / P2 50% / P3 等待 等逐个分P状态。
class _PartProgressRow extends StatelessWidget {
  const _PartProgressRow({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = task.parts;
    if (parts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: parts.map((part) {
        final color = switch (part.status) {
          DownloadStatus.completed => const Color(0xFF4FA36C),
          DownloadStatus.failed => theme.colorScheme.error,
          DownloadStatus.downloading => theme.colorScheme.primary,
          _ => theme.colorScheme.onSurfaceVariant,
        };
        final label = switch (part.status) {
          DownloadStatus.completed => 'P${part.part} ✓',
          DownloadStatus.downloading =>
            'P${part.part} ${(part.progress * 100).round()}%',
          DownloadStatus.paused => 'P${part.part} 已暂停',
          DownloadStatus.failed => 'P${part.part} 失败',
          DownloadStatus.canceled => 'P${part.part} 已取消',
          _ => 'P${part.part} 等待',
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}
