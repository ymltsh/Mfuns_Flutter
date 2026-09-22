import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;

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
        return _quillToMarkdown(ops);
      }
    } on FormatException {
      // Fall through to text rendering below.
    }
  }
  if (!RegExp(r'<[A-Za-z][^>]*>').hasMatch(value)) return value;
  final root = html_parser.parseFragment(value);
  return _renderChildren(
    root.nodes,
  ).replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// 将文章富文本转换成适合系统文本选择与剪贴板的纯文本。
///
/// 阅读页继续使用 Markdown 展示；专用复制页使用此结果，避免把 HTML、
/// Markdown 标记或图片地址一并复制给用户。
String richContentToPlainText(String source) {
  final markdown = normalizeRichContent(source);
  if (markdown.isEmpty) return '';
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
  final blocks = document.parseLines(markdown.split('\n'));
  return blocks
      .map(_plainTextBlock)
      .where((block) => block.isNotEmpty)
      .join('\n\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _plainTextBlock(md.Node node) {
  if (node is md.Text) return node.text.trim();
  if (node is! md.Element) return '';
  switch (node.tag) {
    case 'ul':
      return _plainTextList(node, ordered: false);
    case 'ol':
      return _plainTextList(node, ordered: true);
    case 'blockquote':
      return _plainTextChildren(node).trim();
    case 'hr':
      return '——';
    default:
      return _plainTextChildren(node).trim();
  }
}

String _plainTextList(md.Element list, {required bool ordered}) {
  var index = 1;
  final lines = <String>[];
  for (final child in list.children ?? const <md.Node>[]) {
    if (child is! md.Element || child.tag != 'li') continue;
    final text = _plainTextChildren(child).trim();
    if (text.isEmpty) continue;
    final prefix = ordered ? '${index++}.' : '•';
    lines.add('$prefix $text');
  }
  return lines.join('\n');
}

String _plainTextChildren(md.Element element) =>
    (element.children ?? const <md.Node>[]).map(_plainTextInline).join();

String _plainTextInline(md.Node node) {
  if (node is md.Text) return node.text;
  if (node is! md.Element) return '';
  if (node.tag == 'br') return '\n';
  if (node.tag == 'img') {
    final alt = node.attributes['alt']?.trim() ?? '';
    if (alt.startsWith('sticker:')) {
      return '[${alt.substring('sticker:'.length)}]';
    }
    return alt.isEmpty ? '[图片]' : '[$alt]';
  }
  return _plainTextChildren(node);
}

String _quillToMarkdown(List<dynamic> ops) {
  final output = StringBuffer();
  final line = StringBuffer();

  void finishLine(Map<String, dynamic> attributes) {
    final content = line.toString();
    line.clear();
    if (attributes['header'] != null) {
      final level = (int.tryParse('${attributes['header']}') ?? 1).clamp(1, 6);
      final prefix = List<String>.filled(level, '#').join();
      output.writeln('$prefix $content');
    } else if (attributes['list'] == 'ordered') {
      output.writeln('1. $content');
    } else if (attributes['list'] != null) {
      output.writeln('- $content');
    } else if (attributes['blockquote'] == true) {
      output.writeln('> $content');
    } else if (attributes['code-block'] == true) {
      output.write('```\n$content\n```\n');
    } else {
      output.writeln(content);
    }
  }

  for (final op in ops.whereType<Map<String, dynamic>>()) {
    final attributes = _asAttributes(op['attributes']);
    final insert = op['insert'];
    if (insert is Map<String, dynamic>) {
      final sticker = insert['sticker'];
      if (sticker is String && sticker.isNotEmpty) {
        line.write(
          '![sticker:$sticker]('
          'https://resource.mfuns.net/image/sticker/x.png)',
        );
      }
      final image = safeMediaUri('${insert['image'] ?? ''}');
      if (image != null) line.write('![图片]($image)');
      continue;
    }
    if (insert is! String) continue;
    final pieces = insert.split('\n');
    for (var index = 0; index < pieces.length; index++) {
      if (pieces[index].isNotEmpty) {
        line.write(_formatQuillInline(pieces[index], attributes));
      }
      if (index < pieces.length - 1) finishLine(attributes);
    }
  }
  if (line.isNotEmpty) finishLine(const {});
  return output.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

Map<String, dynamic> _asAttributes(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

String _formatQuillInline(String text, Map<String, dynamic> attributes) {
  var result = text;
  if (attributes['code'] == true) result = '`$result`';
  if (attributes['bold'] == true) result = '**$result**';
  if (attributes['italic'] == true) result = '*$result*';
  if (attributes['strike'] == true) result = '~~$result~~';
  final link = safeHttpUri('${attributes['link'] ?? ''}');
  if (link != null) result = '[$result]($link)';
  return result;
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
      final image = safeMediaUri(node.attributes['src']);
      final isSticker = (node.attributes['class'] ?? '').toLowerCase().contains(
        'sticker',
      );
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

/// 正文图片除了完整 http(s) URL，还可能以 Mfuns 的 `/static/...` 或
/// `static/...` 路径返回。编辑和预览时必须补全 CDN 主机，否则再次保存会
/// 静默丢失这些图片。
Uri? safeMediaUri(String? value) {
  final raw = value?.trim() ?? '';
  if (raw.isEmpty) return null;
  if (raw.startsWith('//')) return safeHttpUri(raw);
  if (raw.startsWith('/')) {
    return Uri.parse('https://cdn2.mfuns.net$raw');
  }
  if (raw.startsWith('static/')) {
    return Uri.parse('https://cdn2.mfuns.net/$raw');
  }
  return safeHttpUri(raw);
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
