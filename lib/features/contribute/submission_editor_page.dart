import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/app_controller.dart';
import '../../core/network/vod_uploader.dart';
import '../../core/theme/app_theme.dart';
import '../content/rich_content_card.dart';
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
  final _tagInput = TextEditingController();
  final _contentFocus = FocusNode();
  final _cover = TextEditingController();
  final List<String> _tags = [];
  final List<SubmissionVideoPart> _videoParts = [];
  int? _categoryId;
  late int _copyright;
  var _draft = false;
  var _isSaving = false;
  var _categoriesLoaded = false;
  var _showPreview = false;

  // 视频上传状态（新建视频投稿时使用）。
  String? _videoPath;
  String? _videoName;
  double _uploadProgress = 0;
  var _isUploading = false;
  int? _replacingPartIndex;

  // 封面本地上传状态。
  var _isUploadingCover = false;
  var _isUploadingArticleImage = false;

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
    _tagInput.dispose();
    _contentFocus.dispose();
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
        _content.text = widget.type == 0
            ? normalizeRichContent(detail.rawContent)
            : detail.content;
        _categoryId = detail.categoryId;
        _tags
          ..clear()
          ..addAll(detail.tags.take(10));
        _cover.text = detail.cover;
        _videoParts
          ..clear()
          ..addAll(detail.videos);
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

  Future<void> _pickVideo({int? replaceIndex}) async {
    if (_isUploading) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final file = result?.files.single;
    final path = file?.path;
    if (file == null || path == null) return;
    setState(() {
      _videoPath = path;
      _videoName = file.name;
      _replacingPartIndex = replaceIndex;
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
      final fallbackTitle = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final replaceIndex = _replacingPartIndex;
      final partTitle = replaceIndex != null &&
              replaceIndex >= 0 &&
              replaceIndex < _videoParts.length &&
              _videoParts[replaceIndex].title.trim().isNotEmpty
          ? _videoParts[replaceIndex].title
          : fallbackTitle;
      setState(() {
        final part = SubmissionVideoPart.direct(
          libraryId,
          title: partTitle,
        );
        if (replaceIndex != null &&
            replaceIndex >= 0 &&
            replaceIndex < _videoParts.length) {
          _videoParts[replaceIndex] = part;
        } else {
          _videoParts.add(part);
        }
        _isUploading = false;
        _uploadProgress = 1;
        _replacingPartIndex = null;
      });
      _toast(replaceIndex == null ? '分P上传完成' : '分P重新上传完成');
    } catch (error) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _replacingPartIndex = null;
        });
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

  void _addTags(Iterable<String> values) {
    var reachedLimit = false;
    setState(() {
      for (final value in values) {
        final tag = value.trim().replaceFirst(RegExp(r'^#+'), '');
        if (tag.isEmpty ||
            _tags.any((item) => item.toLowerCase() == tag.toLowerCase())) {
          continue;
        }
        if (_tags.length >= 10) {
          reachedLimit = true;
          break;
        }
        _tags.add(tag);
      }
    });
    if (reachedLimit) _toast('最多添加 10 个标签');
  }

  void _commitTagInput() {
    final value = _tagInput.text;
    if (value.trim().isEmpty) return;
    _addTags(value.split(RegExp(r'[,，\n]')));
    _tagInput.clear();
  }

  void _handleTagChanged(String value) {
    if (RegExp(r'[,，\n]').hasMatch(value)) _commitTagInput();
  }

  void _wrapSelection(String before, String after, String placeholder) {
    final value = _content.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final selected = selection.textInside(value.text);
    final body = selected.isEmpty ? placeholder : selected;
    final replacement = '$before$body$after';
    final text =
        value.text.replaceRange(selection.start, selection.end, replacement);
    final start = selection.start + before.length;
    _content.value = TextEditingValue(
      text: text,
      selection: selected.isEmpty
          ? TextSelection(baseOffset: start, extentOffset: start + body.length)
          : TextSelection.collapsed(
              offset: selection.start + replacement.length),
    );
    _contentFocus.requestFocus();
  }

  void _prefixLines(String prefix) {
    final value = _content.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final lineStart = selection.start == 0
        ? 0
        : value.text.lastIndexOf('\n', selection.start - 1) + 1;
    final nextBreak = value.text.indexOf('\n', selection.end);
    final lineEnd = nextBreak < 0 ? value.text.length : nextBreak;
    final selected = value.text.substring(lineStart, lineEnd);
    final replacement =
        selected.split('\n').map((line) => '$prefix$line').join('\n');
    _content.value = TextEditingValue(
      text: value.text.replaceRange(lineStart, lineEnd, replacement),
      selection:
          TextSelection.collapsed(offset: lineStart + replacement.length),
    );
    _contentFocus.requestFocus();
  }

  Future<void> _insertArticleImage() async {
    if (_isUploadingArticleImage) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    setState(() => _isUploadingArticleImage = true);
    try {
      final path = await widget.controller.uploadImage(
        await picked.readAsBytes(),
        picked.name,
      );
      if (!mounted) return;
      _wrapSelection('![', '](${_absoluteMediaUrl(path)})', '图片');
      _toast('图片已插入正文');
    } catch (error) {
      if (mounted) _toast('正文图片上传失败：$error');
    } finally {
      if (mounted) setState(() => _isUploadingArticleImage = false);
    }
  }

  Future<void> _removeVideoPart(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分P'),
        content: const Text('保存后该分P将从投稿中移除，已直传的视频不会立即从媒体库删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _videoParts.removeAt(index));
    }
  }

  Future<void> _renameVideoPart(int index) async {
    final input = TextEditingController(text: _videoParts[index].title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改 P${index + 1} 标题'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(hintText: '请输入分P标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    input.dispose();
    if (title == null || title.isEmpty || !mounted) return;
    final old = _videoParts[index];
    setState(() {
      _videoParts[index] = SubmissionVideoPart(
        type: old.type,
        content: old.content,
        title: title,
        meta: old.meta,
        extra: old.extra,
      );
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_isUploading) {
      _toast('请等待视频上传完成');
      return;
    }
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
    if (widget.type == 1 && _videoParts.isEmpty) {
      _toast('请至少保留并上传一个分P');
      return;
    }
    if (widget.type == 1 && _isNew && _cover.text.trim().isEmpty) {
      _toast('视频投稿必须上传封面图');
      return;
    }
    _commitTagInput();
    final tags = List<String>.unmodifiable(_tags);
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
          videos: _videoParts,
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
          videos: _videoParts,
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

  Widget _buildVideoPartsCard() {
    final muted = AppPalette.of(context).muted;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.video_library_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '分P管理（${_videoParts.length}）',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isUploading ? null : () => _pickVideo(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('添加分P'),
                ),
              ],
            ),
            if (_videoParts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Center(
                  child: Text('还没有分P，请先上传视频', style: TextStyle(color: muted)),
                ),
              )
            else
              ...List.generate(_videoParts.length, (index) {
                final part = _videoParts[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    radius: 18,
                    child: Text('P${index + 1}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                  title: Text(
                    part.title.isEmpty ? '未命名分P' : part.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    part.type == 'direct' ? '直传视频' : part.type,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(
                        tooltip: '修改分P标题',
                        onPressed:
                            _isUploading ? null : () => _renameVideoPart(index),
                        icon: const Icon(Icons.edit_outlined, size: 19),
                      ),
                      IconButton(
                        tooltip: '重新上传',
                        onPressed: _isUploading
                            ? null
                            : () => _pickVideo(replaceIndex: index),
                        icon: const Icon(Icons.upload_file_outlined, size: 19),
                      ),
                      IconButton(
                        tooltip: '删除分P',
                        onPressed:
                            _isUploading ? null : () => _removeVideoPart(index),
                        icon:
                            const Icon(Icons.delete_outline_rounded, size: 19),
                      ),
                    ],
                  ),
                );
              }),
            if (_isUploading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 6),
              Text(
                '${_replacingPartIndex == null ? '上传' : '重新上传'}中 '
                '${(_uploadProgress * 100).toStringAsFixed(0)}% · ${_videoName ?? ''}',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildArticleEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
                value: false,
                label: Text('编辑'),
                icon: Icon(Icons.edit_outlined)),
            ButtonSegment(
                value: true,
                label: Text('预览'),
                icon: Icon(Icons.visibility_outlined)),
          ],
          selected: {_showPreview},
          onSelectionChanged: (value) =>
              setState(() => _showPreview = value.first),
        ),
        const SizedBox(height: 10),
        if (_showPreview)
          RichContentCard(source: _content.text)
        else ...[
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Wrap(
                children: [
                  _FormatButton(
                    tooltip: '标题',
                    icon: Icons.title_rounded,
                    onPressed: () => _prefixLines('## '),
                  ),
                  _FormatButton(
                    tooltip: '加粗',
                    icon: Icons.format_bold_rounded,
                    onPressed: () => _wrapSelection('**', '**', '加粗文字'),
                  ),
                  _FormatButton(
                    tooltip: '斜体',
                    icon: Icons.format_italic_rounded,
                    onPressed: () => _wrapSelection('*', '*', '斜体文字'),
                  ),
                  _FormatButton(
                    tooltip: '删除线',
                    icon: Icons.format_strikethrough_rounded,
                    onPressed: () => _wrapSelection('~~', '~~', '删除线文字'),
                  ),
                  _FormatButton(
                    tooltip: '链接',
                    icon: Icons.link_rounded,
                    onPressed: () => _wrapSelection('[', '](https://)', '链接文字'),
                  ),
                  _FormatButton(
                    tooltip: '无序列表',
                    icon: Icons.format_list_bulleted_rounded,
                    onPressed: () => _prefixLines('- '),
                  ),
                  _FormatButton(
                    tooltip: '有序列表',
                    icon: Icons.format_list_numbered_rounded,
                    onPressed: () => _prefixLines('1. '),
                  ),
                  _FormatButton(
                    tooltip: '引用',
                    icon: Icons.format_quote_rounded,
                    onPressed: () => _prefixLines('> '),
                  ),
                  _FormatButton(
                    tooltip: '行内代码',
                    icon: Icons.code_rounded,
                    onPressed: () => _wrapSelection('`', '`', '代码'),
                  ),
                  _FormatButton(
                    tooltip: '代码块',
                    icon: Icons.data_object_rounded,
                    onPressed: () =>
                        _wrapSelection('\n```\n', '\n```\n', '代码块'),
                  ),
                  _FormatButton(
                    tooltip: '插入图片',
                    icon: Icons.add_photo_alternate_outlined,
                    onPressed:
                        _isUploadingArticleImage ? null : _insertArticleImage,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _content,
            focusNode: _contentFocus,
            minLines: 10,
            maxLines: 24,
            decoration: const InputDecoration(
              labelText: '正文',
              hintText: '输入正文，或选中文字后使用上方格式工具',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTagEditor() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '标签',
        helperText: '回车或输入逗号添加，最多 10 个',
        alignLabelWithHint: true,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...List.generate(
            _tags.length,
            (index) => InputChip(
              label: Text(_tags[index]),
              onDeleted: () => setState(() => _tags.removeAt(index)),
            ),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _tagInput,
              enabled: _tags.length < 10,
              decoration: InputDecoration.collapsed(
                hintText: _tags.length >= 10 ? '已达到上限' : '输入标签后回车',
              ),
              textInputAction: TextInputAction.done,
              onChanged: _handleTagChanged,
              onSubmitted: (_) => _commitTagInput(),
            ),
          ),
        ],
      ),
    );
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
          if (isVideo) ...[
            _buildVideoPartsCard(),
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
          if (isVideo)
            TextField(
              controller: _content,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '简介',
                hintText: '视频简介（纯文本）',
                alignLabelWithHint: true,
              ),
            )
          else
            _buildArticleEditor(),
          const SizedBox(height: 12),
          _buildTagEditor(),
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

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      );
}

String _absoluteMediaUrl(String value) {
  final path = value.trim();
  if (path.startsWith('//')) return 'https:$path';
  if (path.startsWith('/')) return 'https://cdn2.mfuns.net$path';
  if (path.startsWith('static/')) return 'https://cdn2.mfuns.net/$path';
  return path;
}
