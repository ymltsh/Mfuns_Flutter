import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../rich_content_normalizer.dart';
import 'article_exporter.dart';
import 'comment_collector.dart';
import 'export_footer.dart';
import 'image_downloader.dart';
import 'markdown_exporter.dart';

/// 导出用 Markdown 基础样式：白底深色文字，适合打印与分享。
///
/// 使用显式带字号的基础 textTheme，避免依赖运行环境 Typography 差异
/// （flutter_markdown_plus 的 fromTheme 要求 bodyMedium.fontSize 非空）。
final MarkdownStyleSheet _exportBaseStyle = MarkdownStyleSheet.fromTheme(
  ThemeData(
    useMaterial3: true,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 14, color: Colors.black87),
      bodyLarge: TextStyle(fontSize: 16, color: Colors.black87),
      bodySmall: TextStyle(fontSize: 12, color: Colors.black54),
      headlineSmall: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w700, color: Colors.black87),
      titleLarge: TextStyle(
          fontSize: 21, fontWeight: FontWeight.w700, color: Colors.black87),
      titleMedium: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
    ),
  ),
).copyWith(
  p: const TextStyle(fontSize: 16, height: 1.85, color: Color(0xFF1F2329)),
  h1: const TextStyle(
      fontSize: 24, height: 1.4, fontWeight: FontWeight.w800, color: Color(0xFF1F2329)),
  h2: const TextStyle(
      fontSize: 21, height: 1.4, fontWeight: FontWeight.w800, color: Color(0xFF1F2329)),
  h3: const TextStyle(
      fontSize: 18, height: 1.4, fontWeight: FontWeight.w800, color: Color(0xFF1F2329)),
  blockquote: const TextStyle(fontSize: 15, height: 1.7, color: Color(0xFF6B7280)),
  code: const TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      color: Color(0xFF1F2329)),
);

/// 把主题色调整为在白底上可读的强调色（亮度收敛到 0.28~0.52）。
Color _onWhite(Color color) {
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness(hsl.lightness.clamp(0.28, 0.52)).toColor();
}

/// 导出用 Markdown 样式（卡片/强调色跟随用户主题取色）。
///
/// 链接、引用块、代码块等"卡片"元素使用 [primary] 派生色，
/// 其余（正文、标题）保持中性深色。
MarkdownStyleSheet _exportMarkdownStyleFor(Color primary) {
  final accent = _onWhite(primary);
  return _exportBaseStyle.copyWith(
    blockquoteDecoration: BoxDecoration(
      color: primary.withOpacity(0.07),
      border: Border(left: BorderSide(color: accent, width: 4)),
      borderRadius: const BorderRadius.all(Radius.circular(4)),
    ),
    code: _exportBaseStyle.code?.copyWith(
      backgroundColor: primary.withOpacity(0.08),
    ),
    codeblockDecoration: BoxDecoration(
      color: primary.withOpacity(0.06),
      borderRadius: const BorderRadius.all(Radius.circular(6)),
    ),
    a: TextStyle(color: accent),
  );
}

/// 长图导出用的文章渲染部件：标题 + 作者 + 正文（Markdown）+ 来源。
///
/// 正文图片使用已解码的 [decodedImages]（url → ui.Image）同步渲染，
/// 保证离屏截取时图片必定已就绪；下载失败的图片渲染为占位框。
class ExportArticleWidget extends StatelessWidget {
  const ExportArticleWidget({
    super.key,
    required this.article,
    required this.markdown,
    required this.decodedImages,
    this.comments = const [],
    this.includeFooter = true,
    this.contentScale = 1.0,
  });

  final ArticleExportData article;
  final String markdown;
  final Map<String, ui.Image> decodedImages;

  /// 附加到正文之后的评论（可为空）。
  final List<ArticleExportComment> comments;

  /// 是否在底部加入 Mfuns Flutter 开源项目说明。
  final bool includeFooter;

  /// 字号缩放比例（仅缩放文本，插图与输出分辨率不变）。
  final double contentScale;

  /// 导出画布逻辑宽度。
  static const double width = 720;

  @override
  Widget build(BuildContext context) {
    final author = article.author.trim();
    // 卡片/强调色跟随用户主题取色（AppPalette.primary）。
    final primary = AppPalette.of(context).primary;
    final style = _exportMarkdownStyleFor(primary);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(contentScale),
      ),
      // 显式提供基础文本样式：导出内容渲染在根 Overlay 中，没有 Material 祖先，
      // 否则纯文本会继承 MaterialApp 的 fallback 样式（红字 + 黄色下划线）。
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFF1F2329), fontSize: 16),
        child: ColoredBox(
      color: const Color(0xFFFFFFFF),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 44, 40, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              article.title.trim().isEmpty ? '未命名文章' : article.title,
              style: const TextStyle(
                  fontSize: 27,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2329)),
            ),
            if (author.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: const Color(0xFFE5E7EB),
                    foregroundColor: const Color(0xFF6B7280),
                    child: Text(
                      author.substring(0, 1),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(author,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 14, color: Color(0xFF6B7280))),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            const SizedBox(height: 20),
            MarkdownBody(
              data: markdown,
              selectable: false,
              imageBuilder: _buildImage,
              styleSheet: style,
            ),
            if (comments.isNotEmpty)
              _ExportCommentSection(
                comments: comments,
                decodedImages: decodedImages,
                imageBuilder: _buildImage,
                styleSheet: style,
              ),
            if (includeFooter) const _ExportFooterSection(),
            if (article.sourceUrl.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('来源：${article.sourceUrl}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            ],
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildImage(Uri uri, String? title, String? alt) {
    final image = decodedImages[uri.toString()];
    final Widget child;
    if (image != null) {
      child = RawImage(
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    } else {
      final label = (alt == null || alt.isEmpty || alt.startsWith('sticker:'))
          ? '图片'
          : alt;
      child = Container(
        height: 120,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: child,
      ),
    );
  }
}

/// 长图中的评论区域：评论标题 + 逐条评论（作者 / 时间 / 内容 / 回复）。
class _ExportCommentSection extends StatelessWidget {
  const _ExportCommentSection({
    required this.comments,
    required this.decodedImages,
    required this.imageBuilder,
    required this.styleSheet,
  });

  final List<ArticleExportComment> comments;
  final Map<String, ui.Image> decodedImages;
  final Widget Function(Uri uri, String? title, String? alt) imageBuilder;
  final MarkdownStyleSheet styleSheet;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),
        const SizedBox(height: 24),
        const Text('评论',
            style: TextStyle(
                fontSize: 22,
                height: 1.4,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2329))),
        const SizedBox(height: 16),
        for (final comment in comments) ...[
          _ExportCommentTile(
            comment: comment,
            decodedImages: decodedImages,
            imageBuilder: imageBuilder,
            styleSheet: styleSheet,
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

class _ExportCommentTile extends StatelessWidget {
  const _ExportCommentTile({
    required this.comment,
    required this.decodedImages,
    required this.imageBuilder,
    required this.styleSheet,
  });

  final ArticleExportComment comment;
  final Map<String, ui.Image> decodedImages;
  final Widget Function(Uri uri, String? title, String? alt) imageBuilder;
  final MarkdownStyleSheet styleSheet;

  @override
  Widget build(BuildContext context) {
    final author =
        comment.author.trim().isEmpty ? '匿名用户' : comment.author.trim();
    final primary = AppPalette.of(context).primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: const Color(0xFFE5E7EB),
              foregroundColor: const Color(0xFF6B7280),
              child: Text(
                author.substring(0, 1),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(author,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2329))),
            ),
            if (comment.createdAt != null) ...[
              const SizedBox(width: 10),
              Text(formatExportDate(comment.createdAt!),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9CA3AF))),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (comment.contentMarkdown.trim().isNotEmpty)
          MarkdownBody(
            data: comment.contentMarkdown,
            selectable: false,
            imageBuilder: imageBuilder,
            styleSheet: styleSheet,
          ),
        if (comment.replies.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: primary.withOpacity(0.05),
              border: Border(
                left: BorderSide(color: _onWhite(primary), width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final reply in comment.replies)
                  _ExportReplyTile(
                    reply: reply,
                    decodedImages: decodedImages,
                    imageBuilder: imageBuilder,
                    styleSheet: styleSheet,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ExportReplyTile extends StatelessWidget {
  const _ExportReplyTile({
    required this.reply,
    required this.decodedImages,
    required this.imageBuilder,
    required this.styleSheet,
  });

  final ArticleExportComment reply;
  final Map<String, ui.Image> decodedImages;
  final Widget Function(Uri uri, String? title, String? alt) imageBuilder;
  final MarkdownStyleSheet styleSheet;

  @override
  Widget build(BuildContext context) {
    final author =
        reply.author.trim().isEmpty ? '匿名用户' : reply.author.trim();
    final date = reply.createdAt == null
        ? ''
        : ' · ${formatExportDate(reply.createdAt!)}';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$author$date',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 4),
          if (reply.contentMarkdown.trim().isNotEmpty)
            MarkdownBody(
              data: reply.contentMarkdown,
              selectable: false,
              imageBuilder: imageBuilder,
              styleSheet: styleSheet,
            ),
        ],
      ),
    );
  }
}

/// 长图底部的开源项目说明：小字号、弱颜色、分割线，不抢正文视觉重点。
class _ExportFooterSection extends StatelessWidget {
  const _ExportFooterSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 32),
        Divider(height: 1, color: Color(0xFFE5E7EB)),
        SizedBox(height: 16),
        Text('关于 ${ExportFooter.projectName}',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280))),
        SizedBox(height: 8),
        Text('本文由 ${ExportFooter.projectName} 导出，这是一个由社区支持的Material Design风格的Mfuns客户端，完全开源免费无广告，请点个star吧！',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        SizedBox(height: 6),
        Text(ExportFooter.repositoryHost,
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
      ],
    );
  }
}

/// 长图导出：固定宽度布局 + 分片离屏渲染 + 始终拼接为一张长图。
///
/// 用户可调整内容大小比例（[ArticleExportOptions.imageScale]）：
/// 仅缩放字号（含行距），插图保持原显示比例，输出分辨率不变
/// （宽度固定 [exportWidth] × [pixelRatio] = 1080px）。
/// 分片捕获保证不一次性生成超大 Bitmap（每片最多 [maxTilePixels] 物理像素），
/// 最后总是合成一张图 —— 超长文章会自动降低像素密度（字号比例不变），
/// 使单张图片像素面积不超过 [maxExportPixels]。
class ImageExporter {
  static const double exportWidth = ExportArticleWidget.width;
  static const double tileHeight = 2048;

  /// 固定像素密度：输出宽度恒为 exportWidth × pixelRatio = 1080px。
  static const double pixelRatio = 1.5;

  /// 单片物理尺寸上限（兼顾老设备纹理上限）。
  static const double maxTilePixels = 4096;

  /// 单张导出图片的最大像素面积（约 72MB RGBA 内存）。
  /// 超长文章自动降低像素密度，保证始终输出一张图。
  static const double maxExportPixels = 18 * 1000 * 1000;

  /// 自动降比例时的像素密度下限（输出宽度不低于 360px）。
  static const double minRatio = 0.5;

  /// 分片规划：每个分片的滚动偏移与视口高度。
  ///
  /// 每片精确覆盖 `[offset, offset + viewport)`，相邻分片无缝衔接，
  /// 最后一片不足一屏时收紧视口（offset 恒为 `i * viewportLogical`，
  /// 不会被 maxScrollExtent 钳制，避免与上一片重叠）。
  @visibleForTesting
  static List<({double offset, double viewport})> tilePlan(
    double contentHeight,
    double viewportLogical,
  ) {
    final totalTiles = (contentHeight / viewportLogical).ceil();
    return [
      for (var i = 0; i < totalTiles; i++)
        (
          offset: i * viewportLogical,
          viewport: math.min(viewportLogical, contentHeight - i * viewportLogical),
        ),
    ];
  }

  static Future<List<ExportResult>> export({
    required BuildContext context,
    required ArticleExportData article,
    required Directory rootDir,
    required ImageDownloader downloader,
    List<ArticleExportComment> comments = const [],
    bool includeFooter = true,
    double imageScale = 1.0,
    ValueChanged<String>? onProgress,
    ExportCancellation? cancellation,
  }) async {
    final markdown =
        stickerCodesFromPlaceholders(normalizeRichContent(article.rawContent));
    if (markdown.trim().isEmpty) {
      throw const ArticleExportException('文章内容为空，无法导出');
    }
    final overlay = Overlay.of(context, rootOverlay: true);

    // 分辨率固定（pixelRatio 恒为基准值），imageScale 仅缩放字号。
    const userRatio = pixelRatio;
    // 字号缩放因子（0.5x~2x），仅影响文本，不影响插图与输出尺寸。
    final contentScale = imageScale.clamp(0.4, 3.0);
    // 视口逻辑高度：保证单片物理高度不超过设备纹理上限。
    final viewportLogical = math.min(tileHeight, maxTilePixels / userRatio);

    final title =
        article.title.trim().isEmpty ? 'mfuns_article' : article.title;
    final safeTitle = sanitizeFileName(title);
    final folder =
        Directory('${rootDir.path}${Platform.pathSeparator}$safeTitle');
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    await folder.create(recursive: true);

    // 评论在长图中只显示文本内容（图片与贴纸占位不渲染），
    // 降低单张图片的面积与内存风险；Markdown 导出不受影响。
    final renderComments = textOnlyComments(comments);

    // 1. 下载并解码正文图片，保证渲染时图片必定可用。
    final urls = extractImageUrls(markdown).toList(growable: false);
    final decodedImages = <String, ui.Image>{};
    var failedImageCount = 0;
    if (urls.isNotEmpty) {
      final imagesDir =
          Directory('${folder.path}${Platform.pathSeparator}.images');
      await imagesDir.create(recursive: true);
      for (var i = 0; i < urls.length; i++) {
        if (cancellation?.isCancelled == true) {
          _disposeImages(decodedImages.values);
          throw const ExportCancelledException();
        }
        onProgress?.call('正在下载图片 ${i + 1}/${urls.length}');
        final local = await downloader.download(
          url: urls[i],
          targetDir: imagesDir,
          fileName: 'img_${(i + 1).toString().padLeft(3, '0')}',
        );
        if (local == null) {
          failedImageCount++;
          continue;
        }
        final decoded = await _decodeImage(File(local));
        if (decoded == null) {
          failedImageCount++;
        } else {
          decodedImages[urls[i]] = decoded;
        }
      }
    }
    // 2. 离屏渲染整篇文章：滚动视口逐屏截取，避免一次性生成超大 Bitmap。
    final key = GlobalKey();
    final childKey = GlobalKey();
    final controller = ScrollController();
    final viewportHeight = ValueNotifier<double>(viewportLogical);
    final entry = OverlayEntry(
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: viewportHeight,
        builder: (_, height, __) => Positioned(
          left: -10000,
          top: -10000,
          child: IgnorePointer(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: exportWidth,
                height: height,
                child: SingleChildScrollView(
                  controller: controller,
                  child: SizedBox(
                    key: childKey,
                    width: exportWidth,
                    child: ExportArticleWidget(
                      article: article,
                      markdown: markdown,
                      decodedImages: decodedImages,
                      comments: renderComments,
                      includeFooter: includeFooter,
                      contentScale: contentScale,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);

    final tiles = <ui.Image>[];
    try {
      await _awaitPaintedFrame();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      // 内容较短时收紧视口高度，避免生成多余空白。
      final contentHeight = childKey.currentContext!.size!.height;
      if (contentHeight <= 0) {
        throw const ArticleExportException('文章渲染失败，请重试');
      }
      // 超长文章自动降低像素密度（字号比例不变），保证始终输出一张图。
      var ratio = userRatio;
      if (contentHeight * exportWidth * ratio * ratio > maxExportPixels) {
        ratio = math.sqrt(maxExportPixels / (contentHeight * exportWidth));
        if (ratio < minRatio) ratio = minRatio;
      }
      if (contentHeight < viewportLogical) {
        viewportHeight.value = contentHeight;
        await _awaitPaintedFrame();
      }

      final plan = tilePlan(contentHeight, viewportLogical);
      for (final (index, step) in plan.indexed) {
        if (cancellation?.isCancelled == true) {
          throw const ExportCancelledException();
        }
        onProgress?.call('正在生成第 ${index + 1}/${plan.length} 张图片…');
        final top = step.offset;
        if (top > 0) {
          // 最后一片可能不足一屏：先收紧视口再滚动到精确偏移，
          // 否则滚动位置会被 maxScrollExtent 钳制，导致与上一片重叠。
          if (step.viewport < viewportLogical) {
            viewportHeight.value = step.viewport;
            await _awaitPaintedFrame();
          }
          controller.jumpTo(math.min(top, controller.position.maxScrollExtent));
          await _awaitPaintedFrame();
        }
        tiles.add(await boundary.toImage(pixelRatio: ratio));
      }

      // 3. 始终拼接为一张长图。
      onProgress?.call('正在合成长图…');
      final physicalWidth = (exportWidth * ratio).round();
      final ui.Image composed;
      if (tiles.length == 1) {
        composed = tiles.first;
      } else {
        final composedHeight =
            tiles.fold<int>(0, (sum, tile) => sum + tile.height);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        var y = 0.0;
        for (final tile in tiles) {
          canvas.drawImage(tile, Offset(0, y), Paint());
          y += tile.height.toDouble();
        }
        composed =
            await recorder.endRecording().toImage(physicalWidth, composedHeight);
      }
      final file = await _writePng(
        image: composed,
        path: '${folder.path}${Platform.pathSeparator}$safeTitle.png',
        onProgress: onProgress,
      );
      if (composed != tiles.first) composed.dispose();
      return [
        ExportResult(
          path: file.path,
          fileName: '$safeTitle.png',
          mimeType: 'image/png',
          failedImageCount: failedImageCount,
        ),
      ];
    } finally {
      for (final tile in tiles) {
        tile.dispose();
      }
      _disposeImages(decodedImages.values);
      entry.remove();
    }
  }

  static Future<File> _writePng({
    required ui.Image image,
    required String path,
    ValueChanged<String>? onProgress,
  }) async {
    onProgress?.call('正在保存图片…');
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    return file;
  }

  static Future<ui.Image?> _decodeImage(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } on Exception {
      return null;
    }
  }

  static void _disposeImages(Iterable<ui.Image> images) {
    for (final image in images) {
      image.dispose();
    }
  }

  /// 请求一帧并等待其结束（保证 Overlay 中新插入的条目完成布局与绘制）。
  static Future<void> _awaitPaintedFrame() async {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }
}
