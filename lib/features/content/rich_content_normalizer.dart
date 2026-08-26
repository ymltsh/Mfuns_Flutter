import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 把服务端返回的富文本（HTML / Quill JSON / 纯文本）规范化为 Markdown。
///
/// 与 UI 解耦的纯函数，供正文渲染（RichContentCard）与文章导出共用，
/// 保证导出内容与页面展示一致，不丢失图片、链接、加粗等信息。
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
      final link = safeHttpUri(node.attributes['href']);
      return link == null || text.isEmpty ? text : '[$text]($link)';
    case 'img':
      final image = safeHttpUri(node.attributes['src']);
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

Uri? safeHttpUri(String? value) {
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
