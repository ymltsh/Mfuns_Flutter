import 'dart:io';

import 'package:flutter/foundation.dart' show ValueChanged;
import 'package:share_plus/share_plus.dart';

import '../content/export/article_exporter.dart'
    show ExportResult, sanitizeFileName;
import '../content/export/export_storage.dart';

/// 视频导出项：一个已下载完成的分P文件。
class VideoExportItem {
  const VideoExportItem({
    required this.part,
    required this.sourcePath,
    required this.title,
    required this.qualityLabel,
  });

  final int part;

  /// 下载目录中的正式文件路径。
  final String sourcePath;

  /// 视频标题（用于导出文件名）。
  final String title;

  /// 清晰度展示文案（如 `1080P`），用于导出文件名。
  final String qualityLabel;
}

/// 视频导出：把已下载完成的本地视频复制到系统公共目录
/// （Android：`Movies/Mfuns Flutter`，桌面：`~/Videos/Mfuns Flutter`），
/// 然后打开系统分享面板。
///
/// 复用文章导出的 [ExportStorage] 基础设施与 Android MediaStore 平台通道。
class VideoExporter {
  const VideoExporter();

  /// 生成导出文件名：`<标题>_P<分P>_<清晰度>.<扩展名>`。
  static String fileNameFor(VideoExportItem item) {
    final base = sanitizeFileName(
        '${item.title}_P${item.part}_${item.qualityLabel}');
    final extension = _extensionOf(item.sourcePath);
    return '$base.$extension';
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot >= path.length - 1) return 'mp4';
    final ext = path.substring(dot + 1).toLowerCase();
    const supported = {
      'mp4', 'flv', 'webm', 'mkv', 'mov', 'ts', 'm4s', 'm3u8', 'mp3', 'm4a', 'aac',
    };
    return supported.contains(ext) ? ext : 'mp4';
  }

  static String _mimeFor(String path) => switch (_extensionOf(path)) {
        'webm' => 'video/webm',
        'mkv' => 'video/x-matroska',
        'flv' => 'video/x-flv',
        'ts' => 'video/mp2t',
        _ => 'video/mp4',
      };

  /// 导出到公共目录；返回持久化后的文件信息（路径为公共目录）。
  ///
  /// 单个文件复制失败时跳过该文件，不中断其余导出。
  static Future<List<ExportResult>> persist(
    List<VideoExportItem> items, {
    ValueChanged<String>? onProgress,
  }) async {
    final results = <ExportResult>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      onProgress?.call('正在保存到本地（${i + 1}/${items.length}）…');
      final source = File(item.sourcePath);
      if (!source.existsSync()) continue;
      final result = ExportResult(
        path: source.path,
        fileName: fileNameFor(item),
        mimeType: _mimeFor(item.sourcePath),
      );
      final saved = await ExportStorage.persist([result]);
      if (saved.isNotEmpty) results.add(saved.first);
    }
    return results;
  }

  /// 打开系统分享面板；Windows 上原生分享不可用时抛出异常，
  /// 由调用方回退为提示保存路径。
  ///
  /// Android 上公共目录文件不在 share_plus FileProvider 根下，
  /// 分享前复制到临时目录。
  static Future<void> share(List<ExportResult> results) async {
    if (results.isEmpty) return;
    final files = <XFile>[];
    for (final result in results) {
      var path = result.path;
      if (Platform.isAndroid) {
        final source = File(path);
        if (source.existsSync()) {
          final temp = File(
              '${Directory.systemTemp.path}${Platform.pathSeparator}'
              'share_${DateTime.now().microsecondsSinceEpoch}_${result.fileName}');
          await source.copy(temp.path);
          path = temp.path;
        }
      }
      files.add(XFile(path, mimeType: result.mimeType));
    }
    await Share.shareXFiles(files);
  }
}
