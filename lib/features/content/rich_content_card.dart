import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/widgets/image_preview_page.dart';
import '../../core/widgets/sticker_image.dart';
import 'rich_content_normalizer.dart';

export 'rich_content_normalizer.dart' show normalizeRichContent;

/// A safe rich-text card for the HTML currently returned by Mfuns and for
/// Markdown supplied by future endpoints. Unsupported HTML is reduced to
/// readable text instead of being executed or silently discarded.
class RichContentCard extends StatelessWidget {
  const RichContentCard({
    super.key,
    required this.source,
    this.padding = const EdgeInsets.all(16),
    this.onLinkTap,
  });

  final String source;
  final EdgeInsetsGeometry padding;

  /// 链接点击回调（用于应用内打开站内链接）；为 null 时复制链接。
  final void Function(String url)? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final markdown = normalizeRichContent(source);
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: padding,
        child: markdown.isEmpty
            ? const Text('正文暂无可展示内容')
            : MarkdownBody(
                data: markdown,
                selectable: true,
                imageBuilder: (uri, _, alt) {
                  if (alt != null && alt.startsWith('sticker:')) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 4),
                      child: StickerImage(
                        stickerKey: alt.substring('sticker:'.length),
                        size: 42,
                      ),
                    );
                  }
                  return _ArticleImage(uri: uri, alt: alt ?? '图片');
                },
                onTapLink: (_, href, __) {
                  final link = safeHttpUri(href);
                  if (link == null) return;
                  if (onLinkTap != null) {
                    onLinkTap!(link.toString());
                    return;
                  }
                  Clipboard.setData(ClipboardData(text: link.toString()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('链接已复制')),
                    );
                  }
                },
                styleSheet:
                    MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.7,
                        color: colors.onSurface,
                      ),
                  h1: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                  h2: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.4,
                      ),
                  h3: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  blockquote: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.6,
                        color: colors.onSurfaceVariant,
                      ),
                  blockquoteDecoration: BoxDecoration(
                    color: colors.primaryContainer.withOpacity(.42),
                    border: Border(
                      left: BorderSide(color: colors.primary, width: 3),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  code: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        backgroundColor: colors.surfaceContainerHighest,
                      ),
                  codeblockDecoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  a: TextStyle(color: colors.primary),
                ),
              ),
      ),
    );
  }
}

class _ArticleImage extends StatelessWidget {
  const _ArticleImage({required this.uri, required this.alt});

  final Uri uri;
  final String alt;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        uri.toString(),
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : SizedBox(
                height: 180,
                child: Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes == null
                        ? null
                        : progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!,
                  ),
                ),
              ),
        errorBuilder: (_, __, ___) => SizedBox(
          height: 100,
          child: Center(child: Text('$alt 加载失败')),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ImagePreviewPage(
            uri: uri,
            alt: alt,
            heroTag: 'article-image-$uri',
          ),
        )),
        child: Hero(tag: 'article-image-$uri', child: image),
      ),
    );
  }
}

