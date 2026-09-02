import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_controller.dart';
import '../../core/network/vod_uploader.dart';
import '../../core/theme/app_theme.dart';
import '../home/home_repository.dart';

/// 投稿编辑器：发布/编辑文章投稿，发布/编辑视频投稿。
class SubmissionEditorPage extends StatefulWidget {
  const SubmissionEditorPage({
    super.key,
    required this.controller,
    required this.type,
    this.contributeId,
  });

  final AppController controller;
  final int type;

  /// 为空时表示新建投稿。
  final int? contributeId;

  @override
  State<SubmissionEditorPage> createState() => _SubmissionEditorPageState();
}

class _SubmissionEditorPageState extends State<SubmissionEditorPage> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _tags = TextEditingController();
  final _cover = TextEditingController();
  int? _categoryId;
  late int _copyright;
  var _draft = false;
  var _isSaving = false;
  var _categoriesLoaded = false;

  // 视频上传状态（新建视频投稿时使用）。
  String? _videoPath;
  String? _videoName;
  int? _videoLibraryId;
  double _uploadProgress = 0;
  var _isUploading = false;

  // 封面本地上传状态。
  var _isUploadingCover = false;

  bool get _isNew => widget.contributeId == null;

  @override
  void initState() {
    super.initState();
    _copyright = widget.type == 1 ? 0 : 2;
    _loadCategories();
    if (!_isNew) _loadDetail();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _tags.dispose();
    _cover.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final controller = widget.controller;
    if (controller.categories.isEmpty && !controller.isLoadingCategories) {
      await controller.loadCategories();
    }
    if (mounted) setState(() => _categoriesLoaded = true);
  }

  Future<void> _loadDetail() async {
    try {
      final detail =
          await widget.controller.submissionDetail(widget.contributeId!);
      if (!mounted) return;
      setState(() {
        _title.text = detail.title;
        _content.text = detail.content;
        _categoryId = detail.categoryId;
        _tags.text = detail.tags.join(',');
        _cover.text = detail.cover;
      });
    } catch (_) {
      // 详情加载失败时允许直接编辑标题等字段。
    }
  }

  List<CategoryNode> get _leafCategories {
    final categories = widget.controller.categories;
    final parentIds =
        categories.map((node) => node.parentId).whereType<int>().toSet();
    final leaves = categories
        .where((node) => !parentIds.contains(node.id))
        .toList(growable: false);
    return leaves.isEmpty ? categories : leaves;
  }

  Future<void> _pickVideo() async {
    if (_isUploading) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final file = result?.files.single;
    final path = file?.path;
    if (file == null || path == null) return;
    setState(() {
      _videoPath = path;
      _videoName = file.name;
      _videoLibraryId = null;
      _uploadProgress = 0;
    });
    await _uploadVideo();
  }

  Future<void> _uploadVideo() async {
    final path = _videoPath;
    final name = _videoName;
    if (path == null || name == null || _isUploading) return;
    setState(() => _isUploading = true);
    try {
      final size = await File(path).length();
      final auth = await widget.controller
          .videoUploadAuth(fileName: name, fileSize: size);
      await uploadVideoToOss(auth, path, onProgress: (sent, total) {
        if (!mounted) return;
        setState(() => _uploadProgress = total == 0 ? 0 : sent / total);
      });
      final libraryId =
          await widget.controller.completeVideoUpload(auth.videoId);
      if (!mounted) return;
      setState(() {
        _videoLibraryId = libraryId;
        _isUploading = false;
        _uploadProgress = 1;
      });
      _toast('视频上传完成，可继续填写信息并发布');
    } catch (error) {
      if (mounted) {
        setState(() => _isUploading = false);
        _toast('视频上传失败：$error');
      }
    }
  }

  Future<void> _pickCover() async {
    if (_isUploadingCover) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 720,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _isUploadingCover = true);
    try {
      final path = await widget.controller.uploadImage(bytes, picked.name);
      if (!mounted) return;
      setState(() => _cover.text = path);
      _toast('封面已上传');
    } catch (error) {
      if (mounted) _toast('封面上传失败：$error');
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  String _coverPreviewUrl() {
    final value = _cover.text.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('//')) return 'https:$value';
    if (value.startsWith('/')) return 'https://cdn2.mfuns.net$value';
    if (value.startsWith('static/')) return 'https://cdn2.mfuns.net/$value';
    return value;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final title = _title.text.trim();
    final content = _content.text.trim();
    if (title.isEmpty) {
      _toast('请输入标题');
      return;
    }
    if (_categoryId == null) {
      _toast('请选择分类');
      return;
    }
    if (widget.type == 0 && content.isEmpty) {
      _toast('请输入正文内容');
      return;
    }
    if (widget.type == 1 && _isNew && _videoLibraryId == null) {
      _toast('请先选择并上传视频文件');
      return;
    }
    if (widget.type == 1 && _isNew && _cover.text.trim().isEmpty) {
      _toast('视频投稿必须上传封面图');
      return;
    }
    final tags = _tags.text
        .split(RegExp(r'[,，]'))
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(10)
        .toList(growable: false);
    setState(() => _isSaving = true);
    try {
      final controller = widget.controller;
      if (widget.type == 0) {
        if (_isNew) {
          await controller.createArticleSubmission(
            title: title,
            content: content,
            categoryId: _categoryId!,
            tags: tags,
            copyright: _copyright,
            cover: _cover.text.trim(),
            draft: _draft,
          );
        } else {
          await controller.updateArticleSubmission(
            contributeId: widget.contributeId!,
            title: title,
            content: content,
            categoryId: _categoryId!,
            tags: tags,
            copyright: _copyright,
            cover: _cover.text.trim(),
            draft: _draft,
          );
        }
      } else if (_isNew) {
        await controller.createVideoSubmission(
          title: title,
          content: content,
          categoryId: _categoryId!,
          videoLibraryId: _videoLibraryId!,
          tags: tags,
          copyright: _copyright,
          cover: _cover.text.trim(),
        );
      } else {
        await controller.updateVideoSubmission(
          contributeId: widget.contributeId!,
          title: title,
          content: content,
          categoryId: _categoryId!,
          tags: tags,
          copyright: _copyright,
          cover: _cover.text.trim(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _isSaving = false);
        _toast('保存失败：$error');
      }
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.type == 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew
            ? (isVideo ? '发布视频' : '发布文章')
            : (isVideo ? '编辑视频投稿' : '编辑文章投稿')),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          if (isVideo && _isNew) ...[
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.video_file_outlined,
                            color: AppPalette.of(context).muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _videoName ?? '选择本地视频文件上传',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppPalette.of(context).muted,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          onPressed: _isUploading ? null : _pickVideo,
                          child: Text(_isUploading ? '上传中…' : '选择文件'),
                        ),
                      ],
                    ),
                    if (_isUploading || _videoLibraryId != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _uploadProgress,
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _isUploading
                            ? '上传中 ${(_uploadProgress * 100).toStringAsFixed(0)}%'
                            : _videoLibraryId != null
                                ? '上传完成，可以发布'
                                : '',
                        style: TextStyle(
                            color: AppPalette.of(context).muted,
                            fontSize: 11.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _title,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: '标题',
              hintText: '请输入标题（最多 30 字）',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          if (_categoriesLoaded)
            DropdownButtonFormField<int>(
              value: _categoryId,
              hint: const Text('选择分类'),
              items: _leafCategories
                  .map((node) => DropdownMenuItem<int>(
                        value: node.id,
                        child: Text(node.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(growable: false),
              onChanged: (value) => setState(() => _categoryId = value),
            )
          else
            const LinearProgressIndicator(),
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            minLines: isVideo ? 3 : 8,
            maxLines: isVideo ? 6 : 20,
            decoration: InputDecoration(
              labelText: isVideo ? '简介' : '正文',
              hintText: isVideo ? '视频简介（纯文本）' : '支持 Markdown 格式的正文内容',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: '标签',
              hintText: '用逗号分隔，最多 10 个',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_coverPreviewUrl().isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _coverPreviewUrl(),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 64,
                      height: 64,
                      color: AppPalette.of(context).placeholder,
                      child: const Icon(Icons.image_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isUploadingCover ? null : _pickCover,
                  icon: _isUploadingCover
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(_isUploadingCover ? '上传中…' : '从相册选择封面'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cover,
            decoration: const InputDecoration(
              labelText: '封面',
              hintText: '封面图片路径或 https 链接（视频投稿必填）',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            value: _copyright,
            decoration: const InputDecoration(labelText: '版权'),
            items: const [
              DropdownMenuItem(value: 2, child: Text('原创')),
              DropdownMenuItem(value: 1, child: Text('转载')),
              DropdownMenuItem(value: 0, child: Text('其他')),
            ],
            onChanged: (value) =>
                setState(() => _copyright = value ?? _copyright),
          ),
          if (!isVideo) ...[
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('仅存草稿，不直接发布'),
              value: _draft,
              onChanged: (value) => setState(() => _draft = value),
            ),
          ],
        ],
      ),
    );
  }
}
