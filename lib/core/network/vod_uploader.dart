import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../features/home/home_repository.dart';
import 'mfuns_api_client.dart';

/// Uploads a local video file to Aliyun OSS with the STS credentials from
/// `/v1/contribute/video/get_upload_auth` using a standard signed PUT
/// (canonical string matching the oss2 SDK used by the reference MCP
/// implementation). Pure Dart, works on every platform.
Future<void> uploadVideoToOss(
  VideoUploadAuth auth,
  String filePath, {
  void Function(int sent, int total)? onProgress,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw const FileSystemException('视频文件不存在');
  }
  final size = await file.length();
  if (size <= 0) {
    throw const FileSystemException('视频文件为空');
  }
  final endpoint = auth.endpoint;
  final bucket = auth.bucket;
  final objectKey = auth.objectKey;
  if (endpoint.isEmpty || bucket.isEmpty || objectKey.isEmpty) {
    throw const MfunsApiException('上传凭证不完整');
  }

  final date = HttpDate.format(DateTime.now().toUtc());
  const contentType = 'application/octet-stream';
  final tokenHeader = auth.securityToken.isEmpty
      ? ''
      : 'x-oss-security-token:${auth.securityToken}\n';
  final canonical = [
    'PUT',
    '',
    contentType,
    date,
    if (tokenHeader.isNotEmpty) tokenHeader.trimRight(),
    '/$bucket/$objectKey',
  ].join('\n');
  final signature = base64.encode(
    Hmac(sha1, utf8.encode(auth.accessKeySecret))
        .convert(utf8.encode(canonical))
        .bytes,
  );

  final uri = Uri.parse('https://$bucket.$endpoint/$objectKey');
  final request = await HttpClient().putUrl(uri);
  request.headers.set(HttpHeaders.dateHeader, date);
  request.headers.set(HttpHeaders.contentTypeHeader, contentType);
  request.headers.contentLength = size;
  if (auth.securityToken.isNotEmpty) {
    request.headers.set('x-oss-security-token', auth.securityToken);
  }
  request.headers.set(
    HttpHeaders.authorizationHeader,
    'OSS ${auth.accessKeyId}:$signature',
  );

  final stream = file.openRead();
  var sent = 0;
  final tracked = stream.transform(
    StreamTransformer<List<int>, List<int>>.fromHandlers(
      handleData: (chunk, sink) {
        sent += chunk.length;
        onProgress?.call(sent, size);
        sink.add(chunk);
      },
    ),
  );
  await request.addStream(tracked);
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw MfunsApiException('OSS 上传失败（${response.statusCode}）：$body');
  }
}
