import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../features/home/home_repository.dart';
import 'emoji_picker_sheet.dart';

/// Comment composer box.
///
/// Stickers picked from the emoji panel are inserted as text markers like
/// `[s-1]` (the same format the official editor uses in sticker alt tags) and
/// are converted into real stickers when the comment is submitted. Uploaded
/// images are shown as removable thumbnails inside the same box.
class InlineEmojiInput extends StatefulWidget {
  const InlineEmojiInput({
    super.key,
    this.hintText = '说点什么…',
    this.fontSize = 15,
    this.onUploadImage,
    this.initialText = '',
  });

  final String hintText;
  final double fontSize;

  /// 预填文本（如“回复 @xxx ”前缀），仅在控件首次创建时生效。
  final String initialText;

  /// Uploads picked image bytes and returns the media path (`/static/...`).
  final Future<String> Function(List<int> bytes, String filename)?
      onUploadImage;

  @override
  State<InlineEmojiInput> createState() => InlineEmojiInputState();
}

class InlineEmojiInputState extends State<InlineEmojiInput> {
  late final TextEditingController _input;
  final List<String> _images = [];
  var _isUploading = false;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initialText);
  }

  /// Text spans with `[pack-id]` markers converted to real stickers, ready
  /// for posting.
  List<CommentSpan> get spans => commentSpansFromText(_input.text);

  List<String> get images => List.unmodifiable(_images);

  bool get isEmpty => _input.text.trim().isEmpty && _images.isEmpty;

  bool get isUploading => _isUploading;

  void clear() {
    _images.clear();
    _input.clear();
  }

  void pickEmoji() {
    EmojiPickerSheet.show(context, (span) {
      if (!mounted) return;
      setState(() {
        _input.text = _input.text +
            (span.isSticker ? '[${span.stickerKey}]' : span.text);
        _input.selection =
            TextSelection.collapsed(offset: _input.text.length);
      });
    });
  }

  Future<void> pickImage() async {
    if (_isUploading || widget.onUploadImage == null) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _isUploading = true);
    try {
      final path = await widget.onUploadImage!(bytes, picked.name);
      if (!mounted) return;
      setState(() => _images.add(path));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('图片上传失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_images.isNotEmpty || _isUploading)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 5,
                runSpacing: 4,
                children: [
                  for (final image in _images)
                    _EmbedThumb(
                      child: Image.network(
                        _imageUrl(image),
                        width: 30,
                        height: 30,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 30,
                          height: 30,
                          child: Icon(Icons.image_outlined, size: 18),
                        ),
                      ),
                      onRemove: () => setState(() => _images.remove(image)),
                    ),
                  if (_isUploading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                ],
              ),
            TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              style: TextStyle(
                  color: Colors.blueGrey, fontSize: widget.fontSize),
              decoration: InputDecoration(
                hintText:
                    _images.isEmpty && _input.text.isEmpty ? widget.hintText : '',
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ],
        ),
      );

  String _imageUrl(String path) {
    if (path.startsWith('//')) return 'https:$path';
    if (path.startsWith('/')) return 'https://cdn2.mfuns.net$path';
    if (path.startsWith('static/')) return 'https://cdn2.mfuns.net/$path';
    return path;
  }
}

class _EmbedThumb extends StatelessWidget {
  const _EmbedThumb({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: const BoxDecoration(
                    color: Color(0xff9a9aa6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded,
                      size: 10, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
}
