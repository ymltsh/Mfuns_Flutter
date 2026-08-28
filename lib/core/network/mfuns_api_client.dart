import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../config/app_config.dart';

class MfunsApiException implements Exception {
  const MfunsApiException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => message;
}

class ApiResponse {
  const ApiResponse({
    required this.code,
    required this.message,
    required this.data,
  });

  final int code;
  final String message;
  final Object? data;
}

/// Small, dependency-free client for the documented Mfuns community API.
///
/// Authentication is deliberately scoped to the community token: it is sent
/// directly in Authorization without a Bearer prefix and is never mixed with
/// the public API-key system.
class MfunsApiClient {
  MfunsApiClient({HttpClient? httpClient})
      : _httpClient = (httpClient ?? HttpClient())
          ..connectionTimeout = const Duration(seconds: 15);

  final HttpClient _httpClient;
  String? _accessToken;

  bool get isAuthenticated => _accessToken?.isNotEmpty ?? false;

  void setAccessToken(String token) => _accessToken = token;

  void clearAccessToken() => _accessToken = null;

  Future<ApiResponse> get(
    String path, {
    Map<String, Object?> query = const {},
  }) {
    return _send('GET', path, query: query);
  }

  Future<ApiResponse> postForm(
    String path,
    Map<String, String> fields,
  ) {
    return _send(
      'POST',
      path,
      body: utf8.encode(Uri(queryParameters: fields).query),
      contentType:
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8'),
    );
  }

  Future<ApiResponse> postJson(
    String path,
    Map<String, Object?> body,
  ) {
    return _send(
      'POST',
      path,
      body: utf8.encode(jsonEncode(body)),
      contentType: ContentType.json,
    );
  }

  /// Uploads a binary file as `multipart/form-data` (used by
  /// `/v1/media/upload_image`). Returns the parsed API response.
  Future<ApiResponse> postMultipart(
    String path, {
    required String field,
    required String filename,
    required List<int> bytes,
    String? fileContentType,
  }) {
    final boundary = 'mfuns-boundary-${DateTime.now().microsecondsSinceEpoch}';
    final body = BytesBuilder();
    void writeText(String text) => body.add(utf8.encode(text));

    writeText('--$boundary\r\n');
    writeText('Content-Disposition: form-data; name="$field"; '
        'filename="$filename"\r\n');
    if (fileContentType != null) {
      writeText('Content-Type: $fileContentType\r\n');
    }
    writeText('\r\n');
    body.add(bytes);
    writeText('\r\n--$boundary--\r\n');

    return _send(
      'POST',
      path,
      body: body.takeBytes(),
      contentType: ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      ),
    );
  }

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    List<int>? body,
    ContentType? contentType,
  }) async {
    final queryParameters = <String, String>{
      for (final entry in query.entries)
        if (entry.value != null) entry.key: '${entry.value}',
    };
    final uri = Uri.https(AppConfig.apiHost, path, queryParameters);

    try {
      final request = await _httpClient.openUrl(method, uri);
      request.headers.set(HttpHeaders.userAgentHeader, AppConfig.userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final token = _accessToken;
      if (token != null && token.isNotEmpty) {
        request.headers.set(HttpHeaders.authorizationHeader, token);
      }
      if (contentType != null) request.headers.contentType = contentType;
      if (body != null) request.add(body);

      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const MfunsApiException('服务器返回了无法识别的数据');
      }

      final code = (decoded['code'] as num?)?.toInt() ?? response.statusCode;
      final message = '${decoded['msg'] ?? '请求失败'}';
      if (response.statusCode >= 400 || code != 1) {
        throw MfunsApiException(message, code: code);
      }
      return ApiResponse(code: code, message: message, data: decoded['data']);
    } on SocketException {
      throw const MfunsApiException('无法连接到 Mfuns，请检查网络后重试');
    } on HttpException {
      throw const MfunsApiException('网络请求失败，请稍后重试');
    } on FormatException {
      throw const MfunsApiException('服务器返回格式异常');
    }
  }
}
