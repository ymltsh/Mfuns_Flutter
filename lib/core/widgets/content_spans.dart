import 'package:flutter/gestures.dart';
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

/// 裸 MV 号（如 mv60751），作为 Mfuns 视频短链识别。
final _mvPattern = RegExp(r'(?<![A-Za-z0-9])mv\d+', caseSensitive: false);

final _trailingPunctuation =
    RegExp(r"[)\]}>.,;:!?，。！？；：、'」』）】]+$");

/// 文本中的一个可点击片段：URL 或 MV 号。
class _LinkMatch {
  const _LinkMatch({
    required this.raw,
    required this.target,
    required this.start,
    required this.end,
  });

  final String raw;
  final String target;
  final int start;
  final int end;
}

/// 合并 URL 与 MV 号匹配，按位置排序并跳过重叠（URL 内含 mv 段时只算 URL）。
List<_LinkMatch> _findLinks(String text) {
  final matches = <_LinkMatch>[];
  for (final match in _linkPattern.allMatches(text)) {
    final raw = match.group(0)!;
    matches.add(_LinkMatch(
      raw: raw,
      target: raw.toLowerCase().startsWith('www.') ? 'https://$raw' : raw,
      start: match.start,
      end: match.end,
    ));
  }
  for (final match in _mvPattern.allMatches(text)) {
    final raw = match.group(0)!;
    matches.add(_LinkMatch(
      raw: raw,
      target: 'https://mfuns.net/${raw.toLowerCase()}',
      start: match.start,
      end: match.end,
    ));
  }
  matches.sort((a, b) => a.start.compareTo(b.start));
  final result = <_LinkMatch>[];
  var lastEnd = -1;
  for (final match in matches) {
    if (match.start < lastEnd) continue;
    result.add(match);
    lastEnd = match.end;
  }
  return result;
}

/// Renders comment/message content spans: plain text with private-pack
/// stickers inline. 文本中的链接会高亮为可点击链接（点击打开、长按复制）；
/// 提供 [onLinkTap] 时点击交给调用方（如应用内打开站内链接）。
class ContentSpans extends StatelessWidget {
  const ContentSpans({
    super.key,
    required this.spans,
    this.textStyle,
    this.stickerSize = 42,
    this.onLinkTap,
  });

  final List<CommentSpan> spans;
  final TextStyle? textStyle;
  final double stickerSize;

  /// 链接点击回调；为 null 时使用系统浏览器打开。
  final void Function(String url)? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final baseStyle = textStyle ??
        const TextStyle(color: Colors.blueGrey, height: 1.4);
    final mentionStyle = TextStyle(
      color: baseStyle.color == Colors.white
          ? Colors.white
          : Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w700,
      height: baseStyle.height,
    );
    return Wrap(
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
          else if (span.isMention)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Text('@${span.mentionName}', style: mentionStyle),
            )
          else
            ..._textSegments(
              span.text,
              baseStyle: baseStyle,
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
  }

  List<Widget> _textSegments(String text, {
    required TextStyle baseStyle,
    required TextStyle linkStyle,
  }) {
    if (text.isEmpty) return const [];
    final segments = <Widget>[];
    var cursor = 0;
    for (final match in _findLinks(text)) {
      if (match.start > cursor) {
        segments.add(Text(text.substring(cursor, match.start),
            style: baseStyle));
      }
      final raw = match.raw;
      final trimmed = _trimTrailingPunctuation(raw);
      if (trimmed.isNotEmpty) {
        final tail = raw.substring(trimmed.length);
        segments.add(_LinkText(
          raw: trimmed,
          target: match.target,
          style: linkStyle,
          onTap: onLinkTap,
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
  const _LinkText({
    required this.raw,
    required this.target,
    required this.style,
    this.onTap,
  });

  final String raw;
  final String target;
  final TextStyle style;

  /// 点击回调；为 null 时使用系统浏览器打开。
  final void Function(String url)? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          if (onTap != null) {
            onTap!(target);
            return;
          }
          launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
        },
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

/// 单段文本中的链接渲染（支持 maxLines/overflow，用于简介等固定行数文本）。
class LinkText extends StatelessWidget {
  const LinkText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.overflow,
    this.onLinkTap,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  /// 链接点击回调；为 null 时使用系统浏览器打开。
  final void Function(String url)? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? const TextStyle(color: Colors.blueGrey);
    final linkStyle = baseStyle.copyWith(
      color: Theme.of(context).colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: Theme.of(context).colorScheme.primary.withOpacity(.5),
    );
    final children = <TextSpan>[];
    var cursor = 0;
    for (final match in _findLinks(text)) {
      if (match.start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final raw = match.raw;
      final trimmed = _trimLinkTrailing(raw);
      if (trimmed.isNotEmpty) {
        children.add(TextSpan(
          text: trimmed,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (onLinkTap != null) {
                onLinkTap!(match.target);
              } else {
                launchUrl(Uri.parse(match.target),
                    mode: LaunchMode.externalApplication);
              }
            },
        ));
        if (raw.length > trimmed.length) {
          children.add(TextSpan(text: raw.substring(trimmed.length)));
        }
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor)));
    }
    if (children.isEmpty) children.add(TextSpan(text: text));
    return Text.rich(
      TextSpan(style: baseStyle, children: children),
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  static String _trimLinkTrailing(String value) {
    var end = value.length;
    while (end > 0 && _trailingPunctuation.hasMatch(value.substring(end - 1))) {
      end--;
    }
    return end <= 0 ? value : value.substring(0, end);
  }
}
