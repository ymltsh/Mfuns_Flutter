import 'dart:io';

import 'package:flutter/foundation.dart';

import '../rich_content_normalizer.dart';
import 'article_exporter.dart';
import 'comment_collector.dart';
import 'export_footer.dart';
import 'image_downloader.dart';

/// 文章内容为空时抛出的导出异常。
class ArticleExportException implements Exception {
  const ArticleExportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 从 Markdown 中提取远程图片 URL（跳过表情贴纸的占位图）。
final _imageUrlPattern = RegExp(
  r'!\[([^\]]*)\]\(\s*(https?://[^\s)]+)\s*\)',
  caseSensitive: false,
);

/// 提取 Markdown 中的远程图片 URL；alt 以 `sticker:` 开头的贴纸占位图除外。
List<String> extractImageUrls(String markdown) {
  final urls = <String>[];
  for (final match in _imageUrlPattern.allMatches(markdown)) {
    final alt = match.group(1) ?? '';
    if (alt.trim().startsWith('sticker:')) continue;
    final url = match.group(2);
    if (url != null && !urls.contains(url)) urls.add(url);
  }
  return urls;
}

/// 把 Markdown 中的远程图片 URL 替换为本地相对路径。
///
/// [localPaths] 为 url → 相对 assets 目录的文件名（如 `assets/image_001.jpg`）；
/// 未下载成功的 URL 保持不变。
String replaceImageUrls(String markdown, Map<String, String> localPaths) {
  if (localPaths.isEmpty) return markdown;
  return markdown.replaceAllMapped(_imageUrlPattern, (match) {
    final alt = match.group(1) ?? '';
    final url = match.group(2) ?? '';
    final local = localPaths[url];
    if (local == null) return match.group(0)!;
    return '![$alt]($local)';
  });
}

/// 把贴纸占位 `![sticker:key](url)` 替换为 `[key]` 代号文本。
///
/// 页面渲染（RichContentCard）仍使用占位形式渲染表情，导出时统一
/// 改为代号，避免贴纸以图片/占位框形式出现在导出内容中。
String stickerCodesFromPlaceholders(String markdown) {
  return markdown.replaceAllMapped(
    RegExp(r'!\[sticker:([^\]]+)\]\([^)]*\)'),
    (match) => '[${match.group(1)}]',
  );
}

/// Markdown 导出：正文经 normalizeRichContent 转为 Markdown，
/// 图片下载到 `<标题>/assets/` 并改写为相对路径。
class MarkdownExporter {
  /// 导出目录结构：
  /// ```text
  /// <标题>/
  /// ├── <标题>.md
  /// └── assets/
  ///     ├── image_001.jpg
  ///     ├── comment_image_001.jpg
  ///     └── ...
  /// ```
  ///
  /// 内容顺序：正文 → 评论（可选）→ 开源项目说明（可选）。
  static Future<ExportResult> export({
    required ArticleExportData article,
    required Directory rootDir,
    required ImageDownloader downloader,
    List<ArticleExportComment> comments = const [],
    bool includeFooter = true,
    ValueChanged<String>? onProgress,
    ExportCancellation? cancellation,
  }) async {
    final articleMarkdown =
        stickerCodesFromPlaceholders(normalizeRichContent(article.rawContent));
    if (articleMarkdown.trim().isEmpty) {
      throw const ArticleExportException('文章内容为空，无法导出');
    }
    final commentsMarkdown = buildCommentsMarkdown(comments);
    final sections = <String>[
      articleMarkdown,
      if (commentsMarkdown.isNotEmpty) commentsMarkdown,
      if (includeFooter) ExportFooter.markdown,
    ];
    final combined = sections.join('\n\n').trim();

    final title =
        article.title.trim().isEmpty ? 'mfuns_article' : article.title;
    final safeTitle = sanitizeFileName(title);
    final folder = Directory('${rootDir.path}${Platform.pathSeparator}$safeTitle');
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    await folder.create(recursive: true);

    var failedImageCount = 0;
    var result = combined;
    // 正文图片与评论图片分开编号：image_NNN / comment_image_NNN。
    final articleUrls = extractImageUrls(articleMarkdown);
    final commentUrls = extractImageUrls(commentsMarkdown);
    if (articleUrls.isNotEmpty || commentUrls.isNotEmpty) {
      final assetsDir =
          Directory('${folder.path}${Platform.pathSeparator}assets');
      await assetsDir.create(recursive: true);
      final localPaths = <String, String>{};
      failedImageCount += await _downloadImages(
        downloader: downloader,
        urls: articleUrls,
        assetsDir: assetsDir,
        prefix: 'image',
        localPaths: localPaths,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      failedImageCount += await _downloadImages(
        downloader: downloader,
        urls: commentUrls,
        assetsDir: assetsDir,
        prefix: 'comment_image',
        localPaths: localPaths,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      result = replaceImageUrls(combined, localPaths);
    }

    if (cancellation?.isCancelled == true) {
      throw const ExportCancelledException();
    }
    onProgress?.call('正在写入 Markdown 文件…');
    final mdFile = File('${folder.path}${Platform.pathSeparator}$safeTitle.md');
    await mdFile.writeAsString(result, flush: true);

    return ExportResult(
      path: mdFile.path,
      fileName: '$safeTitle.md',
      mimeType: 'text/markdown',
      directoryPath: folder.path,
      failedImageCount: failedImageCount,
    );
  }

  static Future<int> _downloadImages({
    required ImageDownloader downloader,
    required List<String> urls,
    required Directory assetsDir,
    required String prefix,
    required Map<String, String> localPaths,
    ValueChanged<String>? onProgress,
    ExportCancellation? cancellation,
  }) async {
    var failed = 0;
    for (var i = 0; i < urls.length; i++) {
      if (cancellation?.isCancelled == true) {
        throw const ExportCancelledException();
      }
      final url = urls[i];
      if (localPaths.containsKey(url)) continue;
      onProgress?.call('正在下载图片 ${i + 1}/${urls.length}');
      final local = await downloader.download(
        url: url,
        targetDir: assetsDir,
        fileName: '${prefix}_${(i + 1).toString().padLeft(3, '0')}',
      );
      if (local == null) {
        failed++;
        continue;
      }
      final fileName = local.split(Platform.pathSeparator).last;
      localPaths[url] = 'assets/$fileName';
    }
    return failed;
  }
}
