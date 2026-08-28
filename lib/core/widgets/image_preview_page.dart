import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 图片查看页：单图或多图（左右滑动切换，双击缩放，可保存当前图片）。
class ImagePreviewPage extends StatefulWidget {
  const ImagePreviewPage({
    super.key,
    required this.uri,
    required this.alt,
    this.heroTag,
    this.uris,
    this.initialIndex = 0,
  });

  final Uri uri;
  final String alt;
  final String? heroTag;

  /// 多图时传入全部图片；为 null 时仅显示 [uri]。
  final List<Uri>? uris;

  /// 多图时初始展示的索引。
  final int initialIndex;

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  static const _galleryChannel = MethodChannel('mfuns/gallery');
  late final PageController _pageController;
  var _index = 0;
  var _isSaving = false;

  int get _count => widget.uris?.length ?? 1;

  Uri get _currentUri => _index < _count ? (_widgetUri(_index)) : widget.uri;

  Uri _widgetUri(int index) =>
      widget.uris != null ? widget.uris![index] : widget.uri;

  bool get _isGallery => _count > 1;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _count - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final uri = _currentUri;
      final request = await HttpClient().getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('图片下载失败（${response.statusCode}）');
      }
      final bytes = await response.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (builder, chunk) => builder..add(chunk),
      );
      final extension = _extensionFor(uri, response.headers.contentType);
      final name = 'mfuns_${DateTime.now().millisecondsSinceEpoch}.$extension';
      await _galleryChannel.invokeMethod<String>('saveImage', {
        'bytes': bytes.takeBytes(),
        'name': name,
        'mimeType': _mimeTypeFor(extension),
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('图片已保存到相册')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(_isGallery
              ? '${widget.alt} ${_index + 1}/$_count'
              : widget.alt),
          actions: [
            IconButton(
              tooltip: '保存图片',
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (!_isGallery) {
              return _ZoomableImage(
                uri: widget.uri,
                heroTag: widget.heroTag ?? 'image-${widget.uri}',
                viewportWidth: constraints.maxWidth,
                viewportHeight: constraints.maxHeight,
              );
            }
            return PageView.builder(
              controller: _pageController,
              itemCount: _count,
              onPageChanged: (value) => setState(() => _index = value),
              itemBuilder: (context, index) => _ZoomableImage(
                uri: _widgetUri(index),
                // 图集禁用 Hero 动画：多图页面返回时目标缩略图可能不在
                // 可视区域或标签不匹配，会产生界面闪动。
                heroTag: null,
                viewportWidth: constraints.maxWidth,
                viewportHeight: constraints.maxHeight,
              ),
            );
          },
        ),
      );
}

/// 单张图片查看：双击缩放、双指缩放平移，占满视口（BoxFit.contain）。
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({
    required this.uri,
    this.heroTag,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  final Uri uri;

  /// 为 null 时不使用 Hero 动画（图集场景）。
  final String? heroTag;
  final double viewportWidth;
  final double viewportHeight;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final _transformation = TransformationController();
  var _zoomedIn = false;

  @override
  void dispose() {
    _transformation.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    setState(() {
      _zoomedIn = !_zoomedIn;
      _transformation.value =
          _zoomedIn ? (Matrix4.identity()..scale(2.5)) : Matrix4.identity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final heroTag = widget.heroTag;
    final image = Image.network(
      widget.uri.toString(),
      width: widget.viewportWidth,
      height: widget.viewportHeight,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                value: progress.expectedTotalBytes == null
                    ? null
                    : progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!,
              ),
            ),
      errorBuilder: (_, __, ___) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 48),
            SizedBox(height: 10),
            Text('图片加载失败',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
    return GestureDetector(
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 5,
        boundaryMargin: const EdgeInsets.all(80),
        transformationController: _transformation,
        child: heroTag == null
            ? image
            : Hero(tag: heroTag, child: image),
      ),
    );
  }
}

String _extensionFor(Uri uri, ContentType? contentType) {
  final path = uri.path.toLowerCase();
  for (final extension in ['png', 'webp', 'gif', 'jpg', 'jpeg']) {
    if (path.endsWith('.$extension')) {
      return extension == 'jpeg' ? 'jpg' : extension;
    }
  }
  switch (contentType?.mimeType) {
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    default:
      return 'jpg';
  }
}

String _mimeTypeFor(String extension) => switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
