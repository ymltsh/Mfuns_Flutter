import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_controller.dart';
import '../../core/theme/app_theme.dart';

/// 发布动态：文本 + 图片 + 标签。
class FeedComposePage extends StatefulWidget {
  const FeedComposePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<FeedComposePage> createState() => _FeedComposePageState();
}

class _FeedComposePageState extends State<FeedComposePage> {
  final _content = TextEditingController();
  final _tags = TextEditingController();
  final List<String> _images = [];
  var _isUploading = false;
  var _isPublishing = false;

  @override
  void dispose() {
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_isUploading || _images.length >= 9) return;
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
      final path = await widget.controller.uploadImage(bytes, picked.name);
      if (!mounted) return;
      setState(() => _images.add(path));
    } catch (error) {
      if (mounted) {
        _toast('图片上传失败：$error');
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _publish() async {
    final content = _content.text.trim();
    if (content.isEmpty) {
      _toast('说点什么吧');
      return;
    }
    if (_isPublishing) return;
    final tags = _tags.text
        .split(RegExp(r'[,，]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(10)
        .toList(growable: false);
    setState(() => _isPublishing = true);
    try {
      await widget.controller.createFeed(
        content: content,
        images: _images,
        tags: tags,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('动态已发布')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _isPublishing = false);
        _toast('发布失败：$error');
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('发布动态'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isPublishing ? null : _publish,
            child: _isPublishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('发布',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          TextField(
            controller: _content,
            minLines: 6,
            maxLines: 14,
            decoration: const InputDecoration(
              hintText: '分享此刻的想法…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          if (_images.isNotEmpty || _isUploading) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final path in _images)
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          _imageUrl(path),
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 72,
                            height: 72,
                            color: const Color(0xffefeff7),
                            child: const Icon(Icons.image_outlined),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: GestureDetector(
                          onTap: () => setState(() => _images.remove(path)),
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: Color(0xff9a9aa6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded,
                                size: 11, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_isUploading)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _images.length >= 9 ? null : _pickImage,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text(_images.length >= 9 ? '最多 9 张图片' : '添加图片'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: '标签',
              hintText: '用逗号分隔，最多 10 个',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 14, color: palette.primary.withOpacity(.7)),
              const SizedBox(width: 5),
              Text('动态发布后将出现在全站时间线',
                  style: TextStyle(
                      color: palette.primary.withOpacity(.7), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  String _imageUrl(String path) {
    if (path.startsWith('//')) return 'https:$path';
    if (path.startsWith('/')) return 'https://cdn2.mfuns.net$path';
    if (path.startsWith('static/')) return 'https://cdn2.mfuns.net/$path';
    return path;
  }
}
