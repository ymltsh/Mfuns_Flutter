import 'dart:convert';
import 'dart:io';

import '../../core/config/app_config.dart';
import '../home/home_repository.dart';

class LatestMfunsException implements Exception {
  const LatestMfunsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LatestMfunsPage {
  const LatestMfunsPage({required this.items, required this.nextBefore});

  final List<LatestMfunsItem> items;
  final double? nextBefore;
}

class LatestMfunsItem {
  const LatestMfunsItem({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.cover,
    required this.createdAt,
    required this.author,
    required this.authorId,
    required this.authorAvatar,
    required this.likes,
    required this.comments,
    required this.views,
    required this.category,
    required this.sourceUrl,
  });

  final int id;
  final String type;
  final String title;
  final String content;
  final String cover;
  final DateTime? createdAt;
  final String author;
  final int? authorId;
  final String authorAvatar;
  final int likes;
  final int comments;
  final int views;
  final String category;
  final String sourceUrl;

  bool get isVideo => type == 'video';
  bool get isArticle => type == 'article';
  bool get isFeed => type == 'feed';
  String get stableId => '$type-$id';

  ContentPreview get contentPreview => ContentPreview(
        id: id,
        title: title.isEmpty ? content : title,
        summary: content,
        cover: cover,
        author: author,
        category: category,
        type: isVideo ? 1 : 0,
        likes: likes,
        comments: comments,
        views: views,
      );

  factory LatestMfunsItem.fromJson(Map<String, dynamic> json) {
    final user = _asMap(json['user']);
    final legacy = user.isEmpty;
    return LatestMfunsItem(
      id: _asInt(json['id']) ?? 0,
      type: '${json['type'] ?? 'feed'}',
      title: '${json['title'] ?? ''}',
      content: '${json['content'] ?? json['description'] ?? ''}',
      cover: _imageUrl(json['cover']),
      createdAt:
          _asDateTime(json['created_at'] ?? json['created_at_timestamp']),
      author: '${user['name'] ?? (legacy ? json['author'] : '') ?? ''}',
      authorId: _asInt(user['id'] ?? (legacy ? json['author_id'] : null)),
      authorAvatar:
          _imageUrl(user['avatar'] ?? (legacy ? json['author_avatar'] : null)),
      likes: _asInt(json['like_count'] ?? json['likes']) ?? 0,
      comments: _asInt(json['comment_count'] ?? json['comments']) ?? 0,
      views: _asInt(json['view_count'] ?? json['views']) ?? 0,
      category: '${json['category_name'] ?? json['category'] ?? ''}',
      sourceUrl: '${json['source_url'] ?? json['url'] ?? ''}',
    );
  }
}

/// A token-free client for the public latest-mfuns source.
class LatestMfunsRepository {
  LatestMfunsRepository({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);

  final HttpClient _httpClient;

  Future<LatestMfunsPage> getLatest({double? before, int limit = 20}) async {
    try {
      return await _getFlutterContract(before: before, limit: limit);
    } on _LatestHttpException catch (error) {
      // Existing deployments exposed /latest before the Flutter-specific
      // contract. Keep the app usable while the service is being upgraded.
      if (error.statusCode != 404) rethrow;
      return _getLegacyContract(before: before, limit: limit);
    }
  }

  Future<LatestMfunsPage> _getFlutterContract({
    required double? before,
    required int limit,
  }) async {
    final data = await _getJson(
      '/api/v1/flutter/latest',
      before: before,
      limit: limit,
    );
    final root = _asMap(data);
    if (_asInt(root['code']) != 1) {
      throw LatestMfunsException('${root['msg'] ?? '最新内容服务请求失败'}');
    }
    final payload = _asMap(root['data']);
    final items = _toItems(payload['list']);
    return LatestMfunsPage(
      items: items,
      nextBefore: _asDouble(payload['next_before']) ??
          (items.isEmpty ? null : _timestamp(items.last.createdAt)),
    );
  }

  Future<LatestMfunsPage> _getLegacyContract({
    required double? before,
    required int limit,
  }) async {
    final data = await _getJson('/latest', before: before, limit: limit);
    final items = _toItems(data);
    return LatestMfunsPage(
      items: items,
      nextBefore: items.isEmpty ? null : _timestamp(items.last.createdAt),
    );
  }

  Future<Object?> _getJson(
    String path, {
    required double? before,
    required int limit,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (before != null) query['before'] = '$before';
    final uri = Uri.https(AppConfig.latestMfunsHost, path, query);
    try {
      final request = await _httpClient.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, AppConfig.userAgent);
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _LatestHttpException(response.statusCode, '最新内容服务不可用');
      }
      return jsonDecode(body);
    } on _LatestHttpException {
      rethrow;
    } on SocketException {
      throw const LatestMfunsException('无法连接到最新内容服务，请检查网络后重试');
    } on HttpException {
      throw const LatestMfunsException('最新内容服务请求失败');
    } on FormatException {
      throw const LatestMfunsException('最新内容服务返回格式异常');
    }
  }
}

class _LatestHttpException implements Exception {
  const _LatestHttpException(this.statusCode, this.message);

  final int statusCode;
  final String message;
}

List<LatestMfunsItem> _toItems(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map(LatestMfunsItem.fromJson)
      .where((item) => item.id != 0)
      .toList(growable: false);
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

double? _asDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

DateTime? _asDateTime(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (parsed != null) return parsed.toLocal();
  }
  final seconds = _asDouble(value);
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round())
      .toLocal();
}

String _imageUrl(Object? value) {
  final url = '${value ?? ''}'.trim();
  if (url.isEmpty) return '';
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('/static/')) return 'https://cdn2.mfuns.net$url';
  if (url.startsWith('static/')) return 'https://cdn2.mfuns.net/$url';
  if (url.startsWith('https://resource.mfuns.net/static/')) {
    return url.replaceFirst(
        'https://resource.mfuns.net', 'https://cdn2.mfuns.net');
  }
  return url;
}

double? _timestamp(DateTime? value) {
  if (value == null) return null;
  return value.millisecondsSinceEpoch.toDouble() / 1000;
}
