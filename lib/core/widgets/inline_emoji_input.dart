import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../features/home/home_repository.dart';
import '../theme/app_theme.dart';
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
    this.onSearchUser,
    this.initialText = '',
  });

  final String hintText;
  final double fontSize;

  /// 预填文本（如“回复 @xxx ”前缀），仅在控件首次创建时生效。
  final String initialText;

  /// Uploads picked image bytes and returns the media path (`/static/...`).
  final Future<String> Function(List<int> bytes, String filename)?
      onUploadImage;

  /// 静默识别用：输入 `@用户名 `（空格结尾）时自动搜索并转为带 id 的
  /// mention。为 null 时关闭该功能。
  final Future<List<UserProfile>> Function(String keyword)? onSearchUser;

  @override
  State<InlineEmojiInput> createState() => InlineEmojiInputState();
}

class InlineEmojiInputState extends State<InlineEmojiInput> {
  late final TextEditingController _input;
  final List<String> _images = [];
  var _isUploading = false;

  /// `@用户名 `（空格结尾）的静默识别正则：`@` 前不能是 `[`（避开
  /// `[@id:名]` 标记），名字不含空格/@/`[`，末尾是空格。
  static final RegExp _mentionPattern = RegExp(r'(?<!\[)@([^\s@\[]+)(?=\s)');

  Timer? _mentionDebounce;
  var _searchSeq = 0;
  var _isReplacing = false;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initialText);
    _input.addListener(_onInputChanged);
  }

  /// 输入变化时防抖触发静默识别。
  void _onInputChanged() {
    if (_isReplacing || widget.onSearchUser == null) return;
    _mentionDebounce?.cancel();
    _mentionDebounce =
        Timer(const Duration(milliseconds: 250), _runSilentMention);
  }

  /// 静默搜索 `@用户名 ` 对应的用户，命中则替换为 `[@id:用户名]` 标记。
  Future<void> _runSilentMention() async {
    final match = _mentionPattern.allMatches(_input.text).lastOrNull;
    if (match == null) return;
    final name = match.group(1)!.trim();
    if (name.isEmpty) return;
    final seq = ++_searchSeq;
    try {
      final users = await widget.onSearchUser!(name);
      if (!mounted || seq != _searchSeq || users.isEmpty) return;
      // 确认期间文本未改动到该区域。
      final text = _input.text;
      if (match.start < 0 || match.end > text.length) return;
      if (text.substring(match.start, match.end) != match.group(0)) return;
      _replaceMention(match, users.first);
    } catch (_) {
      // 静默失败，不打扰输入。
    }
  }

  void _replaceMention(Match match, UserProfile user) {
    if (!mounted) return;
    setState(() {
      _isReplacing = true;
      _mentionDebounce?.cancel();
      final marker = '[@${user.id}:${user.name}]';
      _input.text = _input.text.replaceRange(match.start, match.end, marker);
      _input.selection =
          TextSelection.collapsed(offset: match.start + marker.length);
      _isReplacing = false;
    });
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
        _input.text =
            _input.text + (span.isSticker ? '[${span.stickerKey}]' : span.text);
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
      });
    });
  }

  /// 在光标处插入 `[@用户名]`（无 id）或 `[@id:用户名]`（带 id）标记，
  /// 发送时由 commentSpansFromText 转换为 mention 富文本。
  void addMention(String name, {String id = ''}) {
    if (!mounted || name.trim().isEmpty) return;
    setState(() {
      _isReplacing = true;
      _mentionDebounce?.cancel();
      final trimmed = name.trim();
      final marker = id.isEmpty ? '[@$trimmed]' : '[@$id:$trimmed]';
      final text = _input.text;
      final selection = _input.selection;
      final start = selection.isValid ? selection.start : text.length;
      _input.text = text.replaceRange(start, selection.end, marker);
      _input.selection = TextSelection.collapsed(offset: start + marker.length);
      _isReplacing = false;
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
    _mentionDebounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        decoration: BoxDecoration(
          color: AppPalette.of(context).surface,
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
                  color: AppPalette.of(context).muted,
                  fontSize: widget.fontSize),
              decoration: InputDecoration(
                hintText: _images.isEmpty && _input.text.isEmpty
                    ? widget.hintText
                    : '',
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
                  decoration: BoxDecoration(
                    color: AppPalette.of(context).muted,
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
