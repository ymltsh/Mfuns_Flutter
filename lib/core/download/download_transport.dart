import 'dart:async';
import 'dart:io';

/// 下载错误分类，用于状态提示与自动重试判断。
enum DownloadErrorKind {
  network, // 网络断开 / 连接失败
  timeout, // 请求或读取超时
  http, // HTTP 4xx/5xx
  auth, // 403 / 鉴权失败
  notFound, // 404 / 播放地址失效
  range, // 服务器不支持 Range
  disk, // 磁盘空间不足 / 写入失败
  cancelled, // 用户取消
  unknown,
}

class DownloadException implements Exception {
  const DownloadException(this.message, {this.kind = DownloadErrorKind.unknown});

  final String message;
  final DownloadErrorKind kind;

  /// 瞬时网络类错误可自动重试。
  bool get isTransient =>
      kind == DownloadErrorKind.network || kind == DownloadErrorKind.timeout;

  @override
  String toString() => message;
}

/// 用户主动暂停/取消时抛出，用于中断下载循环。
class DownloadCancelledException implements Exception {
  const DownloadCancelledException();
}

/// 一次 HTTP 响应连接：头部信息 + 响应体字节流。
abstract class DownloadConnection {
  int get statusCode;

  /// 响应体 Content-Length（206 时为本次分段长度）。
  int? get contentLength;

  /// Content-Range: bytes <start>-<end>/<total>。
  int? get contentRangeStart;
  int? get contentRangeEnd;
  int? get contentRangeTotal;

  Stream<List<int>> get body;

  /// 中断响应体读取。
  void abort();
}

/// 下载传输抽象：生产实现基于 dart:io HttpClient（与 MfunsApiClient 一致，
/// 零第三方依赖），测试注入替身以模拟 200/206/403/断网等场景。
abstract class DownloadTransport {
  /// 发起带 Range 的 GET 请求；[offset] 为 0 时不带 Range 头。
  Future<DownloadConnection> connect(
    Uri uri, {
    required Map<String, String> headers,
    required int offset,
  });
}

/// dart:io HttpClient 实现。
class HttpClientDownloadTransport implements DownloadTransport {
  HttpClientDownloadTransport({HttpClient? httpClient})
      : _httpClient = (httpClient ?? HttpClient())
          ..connectionTimeout = const Duration(seconds: 15);

  final HttpClient _httpClient;

  @override
  Future<DownloadConnection> connect(
    Uri uri, {
    required Map<String, String> headers,
    required int offset,
  }) async {
    final request = await _httpClient.openUrl('GET', uri);
    for (final entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    if (offset > 0) {
      request.headers.set('Range', 'bytes=$offset-');
    }
    try {
      final response = await request.close();
      return _HttpClientConnection(request, response);
    } catch (error) {
      throw DownloadException(
        _friendlyError(error),
        kind: _classify(error),
      );
    }
  }

  String _friendlyError(Object error) {
    if (error is SocketException) return '网络连接失败，请检查网络后重试';
    if (error is TimeoutException) return '连接超时，请稍后重试';
    if (error is HttpException) return '网络请求失败，请稍后重试';
    return '网络请求失败：$error';
  }

  DownloadErrorKind _classify(Object error) {
    if (error is TimeoutException) return DownloadErrorKind.timeout;
    if (error is SocketException) return DownloadErrorKind.network;
    return DownloadErrorKind.network;
  }
}

class _HttpClientConnection implements DownloadConnection {
  _HttpClientConnection(this._request, this._response);

  final HttpClientRequest _request;
  final HttpClientResponse _response;

  @override
  int get statusCode => _response.statusCode;

  @override
  int? get contentLength => _response.contentLength;

  @override
  int? get contentRangeStart => _parseContentRange()?.$1;

  @override
  int? get contentRangeEnd => _parseContentRange()?.$2;

  @override
  int? get contentRangeTotal => _parseContentRange()?.$3;

  (int, int, int)? _contentRangeCache;

  (int, int, int)? _parseContentRange() {
    if (_contentRangeCache != null) return _contentRangeCache;
    final header = _response.headers.value('content-range');
    if (header == null) return null;
    // 形如 bytes 0-1023/2048、bytes=0-1023/2048 或 bytes */2048
    final match = RegExp(r'bytes\s*=?\s*(\d+)-(\d+)/(\d+|\*)')
        .firstMatch(header);
    if (match == null) return null;
    final total = match.group(3) == '*'
        ? -1
        : int.tryParse(match.group(3)!) ?? -1;
    final start = int.tryParse(match.group(1)!) ?? -1;
    final end = int.tryParse(match.group(2)!) ?? -1;
    _contentRangeCache = (start, end, total);
    return _contentRangeCache;
  }

  @override
  Stream<List<int>> get body => _response;

  @override
  void abort() {
    try {
      _request.abort();
    } catch (_) {
      // 已关闭时忽略。
    }
  }
}
