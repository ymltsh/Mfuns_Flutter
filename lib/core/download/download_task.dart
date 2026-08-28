import 'dart:convert';

import 'download_status.dart';

/// 分P来源：清晰度在各分P的播放直链。
class DownloadPartSource {
  const DownloadPartSource({required this.part, required this.url});

  final int part;
  final String url;
}

/// 下载任务请求：业务单位是「一个视频 + 一个清晰度」，
/// 由视频详情页按当前所选清晰度收集全部分P的直链构造。
///
/// 媒体 CDN 地址由 `/v1/video/getPlayAddress` 返回（自带签名参数），
/// 下载时**不会**携带社区登录凭证；[headers] 仅包含媒体请求所需头。
class DownloadRequest {
  const DownloadRequest({
    required this.videoId,
    required this.title,
    required this.cover,
    required this.quality,
    required this.qualityLabel,
    required this.parts,
    this.headers = const {},
  });

  final int videoId;
  final String title;
  final String cover;

  /// 清晰度标识（如 `1080p`），用于任务去重与文件名。
  final String quality;

  /// 清晰度展示文案（如 `1080P`）。
  final String qualityLabel;

  /// 全部分P的直链（至少一个）。
  final List<DownloadPartSource> parts;

  /// 媒体请求头（User-Agent / Referer 等），不会包含 Authorization。
  final Map<String, String> headers;

  /// 唯一任务标识：`videoId + quality`。
  String get taskId => DownloadTask.buildTaskId(
        videoId: videoId,
        quality: quality,
      );
}

/// 任务内单个分P的下载状态（持久化在任务记录的 parts_json 中）。
class DownloadPartTask {
  const DownloadPartTask({
    required this.part,
    required this.sourceUrl,
    required this.filePath,
    required this.tempFilePath,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.status,
    this.errorMessage = '',
  });

  final int part;
  final String sourceUrl;

  /// 下载完成后的正式文件路径；只有该文件存在且完成校验后才能离线播放。
  final String filePath;

  /// 未完成下载的临时文件路径（`xxx.mp4.part`）。
  final String tempFilePath;
  final int downloadedBytes;
  final int totalBytes;
  final DownloadStatus status;
  final String errorMessage;

  bool get isPlayable => status == DownloadStatus.completed;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  DownloadPartTask copyWith({
    String? sourceUrl,
    String? filePath,
    String? tempFilePath,
    int? downloadedBytes,
    int? totalBytes,
    DownloadStatus? status,
    String? errorMessage,
  }) {
    return DownloadPartTask(
      part: part,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      filePath: filePath ?? this.filePath,
      tempFilePath: tempFilePath ?? this.tempFilePath,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, Object?> toMap() => {
        'part': part,
        'source_url': sourceUrl,
        'file_path': filePath,
        'temp_file_path': tempFilePath,
        'downloaded_bytes': downloadedBytes,
        'total_bytes': totalBytes,
        'status': status.storageName,
        'error_message': errorMessage,
      };

  factory DownloadPartTask.fromMap(Map<String, Object?> map) {
    return DownloadPartTask(
      part: (map['part'] as num?)?.toInt() ?? 1,
      sourceUrl: '${map['source_url'] ?? ''}',
      filePath: '${map['file_path'] ?? ''}',
      tempFilePath: '${map['temp_file_path'] ?? ''}',
      downloadedBytes: (map['downloaded_bytes'] as num?)?.toInt() ?? 0,
      totalBytes: (map['total_bytes'] as num?)?.toInt() ?? 0,
      status: DownloadStatus.fromStorageName('${map['status'] ?? ''}'),
      errorMessage: '${map['error_message'] ?? ''}',
    );
  }

  @override
  String toString() => 'P$part:$status($downloadedBytes/$totalBytes)';
}

/// 持久化下载任务模型：业务单位是一个视频（含全部分P）。
class DownloadTask {
  const DownloadTask({
    required this.taskId,
    required this.videoId,
    required this.title,
    required this.cover,
    required this.quality,
    required this.qualityLabel,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.createdAt,
    required this.updatedAt,
    required this.parts,
    this.errorMessage = '',
    this.speedBytesPerSecond = 0,
  });

  final String taskId;
  final int videoId;
  final String title;
  final String cover;
  final String quality;
  final String qualityLabel;
  final DownloadStatus status;

  /// 全部分P的已下载字节数之和（汇总进度）。
  final int downloadedBytes;

  /// 已知大小的分P总字节数之和；未知大小的分P不计入。
  final int totalBytes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String errorMessage;

  /// 实时下载速度（字节/秒），仅内存态，不持久化。
  final double speedBytesPerSecond;

  /// 任务内全部分P明细。
  final List<DownloadPartTask> parts;

  /// 唯一标识：`videoId + quality`，避免同一视频同一清晰度重复创建任务。
  static String buildTaskId({
    required int videoId,
    required String quality,
  }) =>
      'v${videoId}_${normalizeQualityKey(quality)}';

  /// 归一化清晰度标识：小写、仅保留字母数字与 `p`/`k`。
  static String normalizeQualityKey(String quality) {
    final normalized = quality
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return normalized.isEmpty ? 'default' : normalized;
  }

  double get progress {
    if (totalBytes <= 0) return 0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isPlayable => status == DownloadStatus.completed;

  int get totalPartCount => parts.length;

  int get completedPartCount =>
      parts.where((part) => part.isPlayable).length;

  /// 该分P是否已可离线播放。
  bool isPartPlayable(int part) =>
      parts.any((p) => p.part == part && p.isPlayable);

  /// 该分P的正式文件路径；未完成时返回 null。
  String? localFileForPart(int part) {
    for (final item in parts) {
      if (item.part == part && item.isPlayable) return item.filePath;
    }
    return null;
  }

  DownloadTask copyWith({
    int? downloadedBytes,
    int? totalBytes,
    DownloadStatus? status,
    String? errorMessage,
    double? speedBytesPerSecond,
    DateTime? updatedAt,
    List<DownloadPartTask>? parts,
  }) {
    return DownloadTask(
      taskId: taskId,
      videoId: videoId,
      title: title,
      cover: cover,
      quality: quality,
      qualityLabel: qualityLabel,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      parts: parts ?? this.parts,
    );
  }

  Map<String, Object?> toMap() => {
        'task_id': taskId,
        'video_id': videoId,
        'title': title,
        'cover': cover,
        'quality': quality,
        'quality_label': qualityLabel,
        'status': status.storageName,
        'downloaded_bytes': downloadedBytes,
        'total_bytes': totalBytes,
        'error_message': errorMessage,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'parts_json': jsonEncode(
          parts.map((part) => part.toMap()).toList(growable: false),
        ),
      };

  factory DownloadTask.fromMap(Map<String, Object?> map) {
    final rawParts = map['parts_json'];
    var parts = <DownloadPartTask>[];
    if (rawParts is String && rawParts.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawParts);
        if (decoded is List) {
          parts = decoded
              .whereType<Map<String, dynamic>>()
              .map(DownloadPartTask.fromMap)
              .toList(growable: false)
            ..sort((a, b) => a.part.compareTo(b.part));
        }
      } catch (_) {
        parts = const [];
      }
    }
    return DownloadTask(
      taskId: '${map['task_id'] ?? ''}',
      videoId: (map['video_id'] as num?)?.toInt() ?? 0,
      title: '${map['title'] ?? ''}',
      cover: '${map['cover'] ?? ''}',
      quality: '${map['quality'] ?? ''}',
      qualityLabel: '${map['quality_label'] ?? ''}',
      status: DownloadStatus.fromStorageName('${map['status'] ?? ''}'),
      downloadedBytes: (map['downloaded_bytes'] as num?)?.toInt() ?? 0,
      totalBytes: (map['total_bytes'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse('${map['created_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse('${map['updated_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      errorMessage: '${map['error_message'] ?? ''}',
      parts: parts,
    );
  }

  Map<String, Object?> toJson() => toMap();

  factory DownloadTask.fromJson(Map<String, Object?> json) =>
      DownloadTask.fromMap(json);

  @override
  String toString() =>
      'DownloadTask($taskId, $status, $downloadedBytes/$totalBytes, '
      'parts=[${parts.join(', ')}], err=$errorMessage)';
}
