import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import 'comment_collector.dart';
import 'export_storage.dart';
import 'image_downloader.dart';
import 'image_exporter.dart';
import 'markdown_exporter.dart';

export 'markdown_exporter.dart' show ArticleExportException;

/// 文章导出格式。
enum ArticleExportFormat { markdown, image }

/// 一次导出的完整配置（Markdown 与图片共用）。
class ArticleExportOptions {
  const ArticleExportOptions({
    required this.format,
    this.includeComments = false,
    this.includeFooter = true,
    this.imageScale = 1.0,
  });

  final ArticleExportFormat format;

  /// 是否把评论包含在导出内容中。
  final bool includeComments;

  /// 是否在导出内容底部加入 Mfuns Flutter 开源项目说明。
  final bool includeFooter;

  /// 图片导出内容大小比例（0.5x ~ 2x，仅图片格式生效）：
  /// 仅缩放字号（含行距），插图保持原显示比例，输出分辨率不变。
  final double imageScale;
}

/// 导出所需的文章数据（详情页已有字段，无需新增 model）。
class ArticleExportData {
  const ArticleExportData({
    required this.title,
    this.author = '',
    required this.rawContent,
    this.authorAvatar = '',
    this.sourceUrl = '',
  });

  final String title;
  final String author;
  final String authorAvatar;
  final String rawContent;

  /// 文章原文链接，用于长图底部来源标注。
  final String sourceUrl;
}

/// 导出结果。
class ExportResult {
  const ExportResult({
    required this.path,
    required this.fileName,
    required this.mimeType,
    this.directoryPath = '',
    this.failedImageCount = 0,
  });

  /// 导出文件的路径（持久化后为公共目录路径）。
  final String path;

  /// 文件显示名（含扩展名）。
  final String fileName;

  final String mimeType;

  /// Markdown 导出时的文章目录（含 assets/ 与 .md 文件）。
  final String directoryPath;

  /// 下载失败而被保留为远程链接的图片数量。
  final int failedImageCount;

  ExportResult copyWith({
    String? path,
    String? fileName,
    String? mimeType,
    String? directoryPath,
    int? failedImageCount,
  }) {
    return ExportResult(
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      directoryPath: directoryPath ?? this.directoryPath,
      failedImageCount: failedImageCount ?? this.failedImageCount,
    );
  }
}

/// 用户主动取消导出。
class ExportCancelledException implements Exception {
  const ExportCancelledException();

  @override
  String toString() => '导出已取消';
}

/// 导出过程中可被 UI 置位的取消标记。
class ExportCancellation {
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  void requestCancel() => _cancelled = true;
}

/// 文章导出统一入口：Markdown 与长图，完成后交给系统分享。
class ArticleExporter {
  ArticleExporter({HttpClient? httpClient})
      : _downloader = ImageDownloader(httpClient: httpClient);

  final ImageDownloader _downloader;

  /// 统一导出入口：生成 → 保存到公共目录（Pictures/Documents · Mfuns Flutter）。
  Future<List<ExportResult>> export(
    BuildContext context,
    ArticleExportData article,
    ArticleExportOptions options, {
    List<ArticleExportComment> comments = const [],
    ValueChanged<String>? onProgress,
    ExportCancellation? cancellation,
  }) async {
    final includeComments =
        options.includeComments ? comments : const <ArticleExportComment>[];
    final List<ExportResult> generated;
    if (options.format == ArticleExportFormat.markdown) {
      generated = [
        await exportMarkdown(
          article,
          comments: includeComments,
          includeFooter: options.includeFooter,
          onProgress: onProgress,
          cancellation: cancellation,
        ),
      ];
    } else {
      generated = await exportImage(
        context,
        article,
        comments: includeComments,
        includeFooter: options.includeFooter,
        imageScale: options.imageScale,
        onProgress: onProgress,
        cancellation: cancellation,
      );
    }
    return ExportStorage.persist(generated, onProgress: onProgress);
  }

  /// 导出 Markdown（图片本地化到 assets/）。
  Future<ExportResult> exportMarkdown(
    ArticleExportData article, {
    List<ArticleExportComment> comments = const [],
    bool includeFooter = true,
    ValueChanged<String>? onProgress,
    ExportCancellation? cancellation,
  }) {
    return MarkdownExporter.export(
      article: article,
      rootDir: exportRoot(),
      downloader: _downloader,
      comments: comments,
      includeFooter: includeFooter,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }

  /// 导出文章长图（始终输出一张图片）。
  Future<List<ExportResult>> exportImage(
    BuildContext context,
    ArticleExportData article, {
    List<ArticleExportComment> comments = const [],
    bool includeFooter = true,
    double imageScale = 1.0,
    ValueChanged<String>? onProgress,
    ExportCancellation? cancellation,
  }) {
    return ImageExporter.export(
      context: context,
      article: article,
      rootDir: exportRoot(),
      downloader: _downloader,
      comments: comments,
      includeFooter: includeFooter,
      imageScale: imageScale,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }

  /// 打开系统分享面板。Windows 上原生分享不可用时会抛出异常，
  /// 由调用方回退为提示保存路径。
  ///
  /// Android 上公共目录文件不在 share_plus FileProvider 根下，
  /// 分享前复制到临时目录。
  Future<void> share(List<ExportResult> results) async {
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

  /// 导出根目录（系统临时目录下，Android 与 Windows 通用）。
  static Directory exportRoot() {
    final directory =
        Directory('${Directory.systemTemp.path}${Platform.pathSeparator}'
            'mfuns_exports');
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }
}

/// 清理文件名中的非法字符，兼容 Android / Windows。
///
/// Windows 非法字符：`<>:"/\|?*`、控制字符、结尾的点和空格；同时限制长度。
String sanitizeFileName(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  const fallback = 'mfuns_article';
  if (cleaned.isEmpty) return fallback;
  return cleaned.length > 48 ? cleaned.substring(0, 48).trimRight() : cleaned;
}
