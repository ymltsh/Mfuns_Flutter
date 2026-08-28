import 'package:flutter/material.dart';

import '../emoji/emoji_pack_store.dart';

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
                color: const Color(0xfff0f0f6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.emoji_emotions_outlined,
                  size: 18, color: Color(0xff999aa6)),
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
              color: const Color(0xfff0f0f6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.emoji_emotions_outlined,
                size: 18, color: Color(0xff999aa6)),
          ),
        );
      },
    );
  }
}
