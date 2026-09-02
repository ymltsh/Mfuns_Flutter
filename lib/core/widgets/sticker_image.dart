import 'package:flutter/material.dart';

import '../emoji/emoji_pack_store.dart';
import '../theme/app_theme.dart';

/// Renders a private-pack sticker by its Quill key (e.g. `s-1`).
///
/// Falls back to a placeholder while the pack list loads or if the key is
/// unknown, so comments never show a broken/blank area.
class StickerImage extends StatelessWidget {
  const StickerImage({super.key, required this.stickerKey, this.size = 42});

  final String stickerKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final key = stickerKey;
    if (key.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<EmojiData>(
      future: EmojiPackStore.instance.load(),
      builder: (context, snapshot) {
        final url = snapshot.data?.stickerUrl(key);
        if (url == null || url.isEmpty) {
          return Tooltip(
            message: '表情',
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.of(context).chip,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(Icons.emoji_emotions_outlined,
                  size: 18, color: AppPalette.of(context).muted),
            ),
          );
        }
        return Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppPalette.of(context).chip,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.emoji_emotions_outlined,
                size: 18, color: AppPalette.of(context).muted),
          ),
        );
      },
    );
  }
}
