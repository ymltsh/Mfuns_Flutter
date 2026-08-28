import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../core/widgets/image_preview_page.dart';
import '../../core/widgets/sticker_image.dart';
import 'rich_content_normalizer.dart';

export 'rich_content_normalizer.dart' show normalizeRichContent;

/// 桌面端（鼠标/触控板）启用 SelectionArea：拖拽即选区，滚动靠滚轮，
/// 与列表滚动无手势冲突。
bool get _useSelectionArea =>
    kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS;

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
    final styleSheet =
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
    );
    // 桌面端用 SelectionArea 让每个段落（SelectableText）之间的选区互通，
    // 长按/拖拽即可跨段落复制正文；触屏端不用 SelectionArea，避免其横向
    // 拖动识别器在斜向滑动时抢走列表的滚动手势导致页面卡住（段落文本仍
    // 支持各自段落内的长按选择复制）。
    final body = MarkdownBody(
      data: markdown,
      selectable: true,
      builders: {
        'pre': _CodeBlockBuilder(
          styleSheet: styleSheet,
          selectable: true,
        ),
      },
      imageBuilder: (uri, _, alt) {
        if (alt != null && alt.startsWith('sticker:')) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
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
      styleSheet: styleSheet,
    );
    return Card(
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: padding,
        child: markdown.isEmpty
            ? const Text('正文暂无可展示内容')
            : (_useSelectionArea ? SelectionArea(child: body) : body),
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

/// 代码块渲染器：保留默认代码块样式（横向滚动 + 背景），并在右上角
/// 叠加“复制代码”按钮。
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.styleSheet, required this.selectable});

  final MarkdownStyleSheet styleSheet;
  final bool selectable;

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => null;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // 与默认渲染一致：去掉末尾换行后按 code 样式展示。
    final code = element.textContent.replaceAll(RegExp(r'\n$'), '');
    if (code.isEmpty) return null;
    final Widget text = selectable
        ? SelectableText.rich(
            TextSpan(style: styleSheet.code, text: code),
            textScaler: styleSheet.textScaler,
          )
        : Text.rich(
            TextSpan(style: styleSheet.code, text: code),
            textScaler: styleSheet.textScaler,
          );
    // 右侧留出复制按钮的宽度，避免按钮遮挡代码首行内容。
    final basePadding = styleSheet.codeblockPadding ?? const EdgeInsets.all(8);
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: styleSheet.codeblockDecoration,
      child: Stack(
        children: [
          _CodeBlockScrollView(
            padding: basePadding.add(const EdgeInsets.only(right: 72)),
            child: text,
          ),
          Positioned(
            top: 6,
            right: 6,
            child: _CopyCodeButton(code: code),
          ),
        ],
      ),
    );
  }
}

/// 代码块的横向滚动容器（带滚动条），行为与默认渲染一致。
class _CodeBlockScrollView extends StatefulWidget {
  const _CodeBlockScrollView({required this.padding, required this.child});

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<_CodeBlockScrollView> createState() => _CodeBlockScrollViewState();
}

class _CodeBlockScrollViewState extends State<_CodeBlockScrollView> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          child: widget.child,
        ),
      );
}

/// 代码块右上角的“复制代码”按钮：点击后写入剪贴板并短暂显示反馈。
class _CopyCodeButton extends StatefulWidget {
  const _CopyCodeButton({required this.code});

  final String code;

  @override
  State<_CopyCodeButton> createState() => _CopyCodeButtonState();
}

class _CopyCodeButtonState extends State<_CopyCodeButton> {
  var _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _copied
        ? const Color(0xFF34C759)
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: theme.colorScheme.surface.withOpacity(.92),
      borderRadius: BorderRadius.circular(8),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _copy,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(
                _copied ? '已复制' : '复制',
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

