import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/widgets/image_preview_page.dart';
import '../../core/widgets/sticker_image.dart';

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
                  final link = _safeUri(href);
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

String normalizeRichContent(String source) {
  final value = source.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('{')) {
    // Quill JSON content (some endpoints return it despite html=1): convert
    // to markdown so text and stickers render like the HTML path.
    try {
      final decoded = jsonDecode(value);
      final ops = decoded is Map<String, dynamic> ? decoded['ops'] : null;
      if (ops is List) {
        final buffer = StringBuffer();
        for (final op in ops.whereType<Map<String, dynamic>>()) {
          final insert = op['insert'];
          if (insert is String) {
            buffer.write(insert.trimRight());
          } else if (insert is Map<String, dynamic>) {
            final sticker = insert['sticker'];
            if (sticker is String && sticker.isNotEmpty) {
              buffer.write(
                  '![sticker:$sticker](https://resource.mfuns.net/image/sticker/x.png)');
            }
          }
        }
        return buffer
            .toString()
            .replaceAll(RegExp(r'\n{3,}'), '\n\n')
            .trim();
      }
    } on FormatException {
      // Fall through to text rendering below.
    }
  }
  if (!RegExp(r'<[A-Za-z][^>]*>').hasMatch(value)) return value;
  final root = html_parser.parseFragment(value);
  return _renderChildren(root.nodes)
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _renderChildren(Iterable<dom.Node> nodes) =>
    nodes.map(_renderNode).join();

String _renderNode(dom.Node node) {
  if (node is dom.Text) return node.data;
  if (node is! dom.Element) return '';

  final tag = node.localName?.toLowerCase() ?? '';
  final text = _renderChildren(node.nodes).trim();
  switch (tag) {
    case 'br':
      return '\n';
    case 'p':
    case 'div':
    case 'section':
      return text.isEmpty ? '\n' : '$text\n\n';
    case 'h1':
      return '# $text\n\n';
    case 'h2':
      return '## $text\n\n';
    case 'h3':
      return '### $text\n\n';
    case 'h4':
      return '#### $text\n\n';
    case 'strong':
    case 'b':
      return text.isEmpty ? '' : '**$text**';
    case 'em':
    case 'i':
      return text.isEmpty ? '' : '*$text*';
    case 's':
    case 'strike':
    case 'del':
      return text.isEmpty ? '' : '~~$text~~';
    case 'blockquote':
      final quote = text
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .map((line) => '> ${line.trim()}')
          .join('\n');
      return '$quote\n\n';
    case 'pre':
      return text.isEmpty ? '' : '\n```\n$text\n```\n\n';
    case 'code':
      return node.parent?.localName == 'pre' || text.isEmpty ? text : '`$text`';
    case 'ul':
      return _renderList(node, ordered: false);
    case 'ol':
      return _renderList(node, ordered: true);
    case 'li':
      return text;
    case 'a':
      final link = _safeUri(node.attributes['href']);
      return link == null || text.isEmpty ? text : '[$text]($link)';
    case 'img':
      final image = _safeUri(node.attributes['src']);
      final isSticker =
          (node.attributes['class'] ?? '').toLowerCase().contains('sticker');
      if (isSticker) {
        final key = _stickerKey(node.attributes['alt'], node.attributes['src']);
        if (key != null && image != null) return '![sticker:$key]($image)';
      }
      final alt = node.attributes['alt']?.trim() ?? '图片';
      return image == null ? '' : '![$alt]($image)\n\n';
    default:
      return _renderChildren(node.nodes);
  }
}

String _renderList(dom.Element list, {required bool ordered}) {
  var index = 1;
  final lines = <String>[];
  for (final child in list.children.where((item) => item.localName == 'li')) {
    final text = _renderChildren(child.nodes).trim();
    if (text.isEmpty) continue;
    lines.add('${ordered ? '${index++}.' : '-'} $text');
  }
  return lines.isEmpty ? '' : '${lines.join('\n')}\n\n';
}

Uri? _safeUri(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  final normalized = raw.startsWith('//') ? 'https:$raw' : raw;
  final uri = Uri.tryParse(normalized);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  return uri;
}

/// Extracts the `pack-id` sticker key from an `<img>` alt (`[s-1]`) or from
/// its resource path (`.../sticker/s/1.png` → `s-1`).
String? _stickerKey(String? alt, String? src) {
  if (alt != null) {
    final trimmed = alt.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      final key = trimmed.substring(1, trimmed.length - 1).trim();
      if (key.isNotEmpty) return key;
    }
  }
  if (src == null) return null;
  final segments = Uri.tryParse(src)?.pathSegments ?? const <String>[];
  if (segments.length < 2) return null;
  final id = segments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
  return '${segments[segments.length - 2]}-$id';
}
