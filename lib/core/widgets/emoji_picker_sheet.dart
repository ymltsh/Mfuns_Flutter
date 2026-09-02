import 'package:flutter/material.dart';

import '../emoji/emoji_pack_store.dart';
import '../theme/app_theme.dart';
import '../../features/home/home_repository.dart';
import 'sticker_image.dart';

/// Bottom-sheet emoji picker for the comment composer.
///
/// Shows every private pack returned by `/v1/emoji_pack/list` plus the
/// face-text list from `/v1/emoji_pack/face_text`. Tapping an item calls
/// [onPick] and keeps the sheet open so several stickers can be inserted
/// before closing it with 完成.
class EmojiPickerSheet extends StatelessWidget {
  const EmojiPickerSheet({super.key, required this.onPick});

  final ValueChanged<CommentSpan> onPick;

  static Future<void> show(
    BuildContext context,
    ValueChanged<CommentSpan> onPick,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => EmojiPickerSheet(onPick: onPick),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .52,
          child: FutureBuilder<EmojiData>(
            future: EmojiPackStore.instance.load(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Text('表情包加载失败：${snapshot.error}',
                      style: TextStyle(color: AppPalette.of(context).muted)),
                );
              }
              final data = snapshot.requireData;
              final packTabs = data.packs;
              final tabLabels = <String>[
                ...packTabs.map((pack) => pack.name),
                if (data.faceTexts.isNotEmpty) '颜文字',
              ];
              return DefaultTabController(
                length: tabLabels.length,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('选择表情',
                                style: TextStyle(
                                    color: AppPalette.of(context).muted,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('完成'),
                          ),
                        ],
                      ),
                    ),
                    TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: Theme.of(context).colorScheme.primary,
                      unselectedLabelColor: AppPalette.of(context).muted,
                      dividerColor: Colors.transparent,
                      tabs: tabLabels.map((label) => Tab(text: label)).toList(),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          for (final pack in packTabs)
                            _StickerPackGrid(pack: pack, onPick: onPick),
                          if (data.faceTexts.isNotEmpty)
                            _FaceTextGrid(
                                faces: data.faceTexts, onPick: onPick),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
}

class _StickerPackGrid extends StatelessWidget {
  const _StickerPackGrid({required this.pack, required this.onPick});

  final EmojiPack pack;
  final ValueChanged<CommentSpan> onPick;

  @override
  Widget build(BuildContext context) {
    final stickers = pack.stickers.values.toList(growable: false);
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 76,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, index) {
        final sticker = stickers[index];
        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onPick(CommentSpan.sticker('${pack.key}-${sticker.id}')),
          child: StickerImage(
            stickerKey: '${pack.key}-${sticker.id}',
            size: 56,
          ),
        );
      },
    );
  }
}

class _FaceTextGrid extends StatelessWidget {
  const _FaceTextGrid({required this.faces, required this.onPick});

  final List<String> faces;
  final ValueChanged<CommentSpan> onPick;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: faces.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onPick(CommentSpan.text(faces[index])),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.of(context).chip,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(faces[index],
                style: TextStyle(
                    color: AppPalette.of(context).muted, fontSize: 14)),
          ),
        ),
      );
}
