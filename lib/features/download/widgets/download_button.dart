import 'package:flutter/material.dart';

import '../../../core/download/download_status.dart';
import '../../../core/download/download_task.dart';

/// 下载入口按钮：根据任务状态显示“下载 / 下载中 xx% / 已暂停 /
/// 下载失败 / 已下载 / 已取消”。
class DownloadButton extends StatelessWidget {
  const DownloadButton({
    super.key,
    required this.task,
    required this.onTap,
  });

  /// 当前（videoId + part + quality）对应的任务；null 表示尚未创建。
  final DownloadTask? task;

  final VoidCallback onTap;

  (IconData, String) get _visual {
    final task = this.task;
    if (task == null) return (Icons.download_rounded, '下载');
    switch (task.status) {
      case DownloadStatus.downloading:
        return (Icons.downloading_rounded,
            '下载中 ${(task.progress * 100).round()}%');
      case DownloadStatus.paused:
        return (Icons.pause_circle_outline_rounded, '已暂停');
      case DownloadStatus.failed:
        return (Icons.error_outline_rounded, '下载失败');
      case DownloadStatus.canceled:
        return (Icons.replay_circle_filled_outlined, '已取消');
      case DownloadStatus.completed:
        return (Icons.check_circle_outline_rounded, '已下载');
      case DownloadStatus.pending:
        return (Icons.hourglass_top_rounded, '排队中');
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _visual;
    final color = switch (task?.status) {
      DownloadStatus.failed => Theme.of(context).colorScheme.error,
      DownloadStatus.completed => const Color(0xFF4FA36C),
      DownloadStatus.downloading => Theme.of(context).colorScheme.primary,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: SizedBox(
        width: 56,
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
