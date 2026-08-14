import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ImagePreviewPage extends StatefulWidget {
  const ImagePreviewPage({
    super.key,
    required this.uri,
    required this.alt,
    this.heroTag,
  });

  final Uri uri;
  final String alt;
  final String? heroTag;

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  static const _galleryChannel = MethodChannel('mfuns/gallery');
  var _isSaving = false;
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

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final request = await HttpClient().getUrl(widget.uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('图片下载失败（${response.statusCode}）');
      }
      final bytes = await response.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (builder, chunk) => builder..add(chunk),
      );
      final extension = _extensionFor(widget.uri, response.headers.contentType);
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
          title: Text(widget.alt),
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
            // The image fills the viewport (letterboxed by BoxFit.contain)
            // instead of rendering at its natural resolution, so zooming
            // pans within the screen and never crops at the source size.
            // boundaryMargin lets the zoomed image travel past the edges so
            // every corner stays reachable.
            final viewportWidth = constraints.maxWidth;
            final viewportHeight = constraints.maxHeight;
            return GestureDetector(
              onDoubleTap: _toggleZoom,
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                boundaryMargin: const EdgeInsets.all(80),
                transformationController: _transformation,
                child: Hero(
                tag: widget.heroTag ?? 'image-${widget.uri}',
                child: Image.network(
                  widget.uri.toString(),
                  width: viewportWidth,
                  height: viewportHeight,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) =>
                      progress == null
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
                ),
                ),
              ),
            );
          },
        ),
      );
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
