import 'package:flutter/material.dart';

/// 通用字节格式化。
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes < 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(decimals)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(decimals)} MB';
  return '${(mb / 1024).toStringAsFixed(decimals)} GB';
}

/// 下载进度条：百分比 + 已下载/总大小 + 实时速度。
class DownloadProgress extends StatelessWidget {
  const DownloadProgress({
    super.key,
    required this.downloadedBytes,
    required this.totalBytes,
    this.speedBytesPerSecond = 0,
  });

  final int downloadedBytes;
  final int totalBytes;
  final double speedBytesPerSecond;

  double get _progress {
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  int get _percent => (_progress * 100).round();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeText = totalBytes > 0
        ? '${formatBytes(downloadedBytes)} / ${formatBytes(totalBytes)}'
        : formatBytes(downloadedBytes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                speedBytesPerSecond > 0
                    ? '$sizeText · ${formatBytes(speedBytesPerSecond.toInt())}/s'
                    : sizeText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              totalBytes > 0 ? '$_percent%' : '--',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: totalBytes > 0 ? _progress : null,
            minHeight: 6,
            backgroundColor:
                theme.colorScheme.onSurface.withOpacity(.1),
          ),
        ),
      ],
    );
  }
}
