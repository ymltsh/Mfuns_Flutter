import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/home/home_repository.dart';
import 'sticker_image.dart';

/// 识别文本中的链接（http/https/www 开头，仅匹配 URL 合法字符，避免
/// 吞掉后面紧跟的中文），并去掉常见的结尾标点。
final _linkPattern = RegExp(
  r'(https?://|www\.)[a-zA-Z0-9\-._~:/?#\[\]@!$&()*+,;=%]+',
  caseSensitive: false,
);
final _trailingPunctuation =
    RegExp(r"[)\]}>.,;:!?，。！？；：、'」』）】]+$");

/// Renders comment/message content spans: plain text with private-pack
/// stickers inline. 文本中的链接会高亮为可点击链接（点击打开、长按复制）。
class ContentSpans extends StatelessWidget {
  const ContentSpans({
    super.key,
    required this.spans,
    this.textStyle,
    this.stickerSize = 42,
  });

  final List<CommentSpan> spans;
  final TextStyle? textStyle;
  final double stickerSize;

  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 2,
        runSpacing: 4,
        children: [
          for (final span in spans)
            if (span.isSticker)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: StickerImage(
                    stickerKey: span.stickerKey, size: stickerSize),
              )
            else
              ..._textSegments(
                span.text,
                baseStyle: textStyle ??
                    const TextStyle(color: Colors.blueGrey, height: 1.4),
                linkStyle: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  decoration: TextDecoration.underline,
                  decorationColor:
                      Theme.of(context).colorScheme.primary.withOpacity(.5),
                  height: 1.4,
                ),
              ),
        ],
      );

  List<Widget> _textSegments(String text, {
    required TextStyle baseStyle,
    required TextStyle linkStyle,
  }) {
    if (text.isEmpty) return const [];
    final segments = <Widget>[];
    var cursor = 0;
    for (final match in _linkPattern.allMatches(text)) {
      if (match.start > cursor) {
        segments.add(Text(text.substring(cursor, match.start),
            style: baseStyle));
      }
      final raw = text.substring(match.start, match.end);
      final trimmed = _trimTrailingPunctuation(raw);
      if (trimmed.isNotEmpty) {
        final tail = raw.substring(trimmed.length);
        segments.add(_LinkText(
          raw: trimmed,
          style: linkStyle,
        ));
        if (tail.isNotEmpty) {
          segments.add(Text(tail, style: baseStyle));
        }
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      segments.add(Text(text.substring(cursor), style: baseStyle));
    }
    if (segments.isEmpty) segments.add(Text(text, style: baseStyle));
    return segments;
  }

  static String _trimTrailingPunctuation(String value) {
    var end = value.length;
    while (end > 0 && _trailingPunctuation.hasMatch(value.substring(end - 1))) {
      end--;
    }
    return end <= 0 ? value : value.substring(0, end);
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.raw, required this.style});

  final String raw;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final target = raw.toLowerCase().startsWith('www.')
        ? 'https://$raw'
        : raw;
    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(target),
          mode: LaunchMode.externalApplication),
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: raw));
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('链接已复制')));
        }
      },
      child: Text(raw, style: style),
    );
  }
}
