import 'dart:async';
import 'dart:io';

/// 图片下载：复用项目现有 dart:io HttpClient 网络层，
/// 支持 URL 去重、扩展名推断与失败容忍（失败返回 null，不抛异常）。
class ImageDownloader {
  ImageDownloader({HttpClient? httpClient})
      : _http = httpClient ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final HttpClient _http;

  /// 单张图片下载超时。
  static const timeout = Duration(seconds: 20);

  /// 本次实例已下载成功的 url → 本地文件路径（相同 URL 不重复下载）。
  final Map<String, String> _cache = <String, String>{};

  /// 下载 [url] 到 [targetDir]/[fileName]，文件名不含扩展名。
  ///
  /// 返回本地绝对路径；下载失败返回 null（调用方保留远程 URL 继续导出）。
  Future<String?> download({
    required String url,
    required Directory targetDir,
    required String fileName,
  }) async {
    final cached = _cache[url];
    if (cached != null) return cached;
    try {
      final request = await _http.getUrl(Uri.parse(url)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;
      final extension =
          inferImageExtension(url, response.headers.contentType?.mimeType);
      final file = File(
          '${targetDir.path}${Platform.pathSeparator}$fileName.$extension');
      final sink = file.openWrite();
      await response.pipe(sink).timeout(timeout);
      await sink.close();
      _cache[url] = file.path;
      return file.path;
    } on Exception {
      // 网络 / 超时 / IO 失败均容忍，由调用方决定是否继续。
      return null;
    }
  }
}

const _knownExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'svg',
  'avif',
};

/// 依据 URL 路径或响应 Content-Type 推断图片扩展名。
String inferImageExtension(String url, String? mimeType) {
  final path = Uri.tryParse(url)?.path ?? '';
  final dot = path.lastIndexOf('.');
  if (dot >= 0 && dot < path.length - 1) {
    final candidate =
        path.substring(dot + 1).toLowerCase().split('?').first;
    if (_knownExtensions.contains(candidate)) {
      return candidate == 'jpeg' ? 'jpg' : candidate;
    }
  }
  return switch (mimeType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
    'image/gif' => 'gif',
    'image/svg+xml' => 'svg',
    'image/bmp' => 'bmp',
    _ => 'img',
  };
}
