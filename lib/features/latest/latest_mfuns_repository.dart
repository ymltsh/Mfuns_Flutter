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
    this.markCount = 0,
    this.markedByMe = false,
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

  /// 已有多少位喵友标记此帖子为不友好。
  final int markCount;

  /// 当前用户是否已标记。
  final bool markedByMe;

  bool get isVideo => type == 'video';
  bool get isArticle => type == 'article';
  bool get isFeed => type == 'feed';
  String get stableId => '$type-$id';

  LatestMfunsItem copyWith({int? markCount, bool? markedByMe}) =>
      LatestMfunsItem(
        id: id,
        type: type,
        title: title,
        content: content,
        cover: cover,
        createdAt: createdAt,
        author: author,
        authorId: authorId,
        authorAvatar: authorAvatar,
        likes: likes,
        comments: comments,
        views: views,
        category: category,
        sourceUrl: sourceUrl,
        markCount: markCount ?? this.markCount,
        markedByMe: markedByMe ?? this.markedByMe,
      );

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
      markCount: _asInt(json['mark_count']) ?? 0,
      markedByMe: json['marked_by_me'] == true,
    );
  }
}

/// 不友好标记结果。
class LatestMarkResult {
  const LatestMarkResult({required this.markCount, required this.blocked});

  final int markCount;
  final bool blocked;
}

/// A token-free client for the public latest-mfuns source.
class LatestMfunsRepository {
  LatestMfunsRepository({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient()
          ..connectionTimeout = const Duration(seconds: 15);

  final HttpClient _httpClient;

  Future<LatestMfunsPage> getLatest({
    double? before,
    int limit = 20,
    String user = '',
  }) async {
    try {
      return await _getFlutterContract(before: before, limit: limit, user: user);
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
    required String user,
  }) async {
    final data = await _getJson(
      '/api/v1/flutter/latest',
      before: before,
      limit: limit,
      user: user,
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

  /// 不友好标记（同一用户对同一帖子只计一次，达到 5 人自动屏蔽）。
  Future<LatestMarkResult> markItem({
    required int id,
    required String type,
    required String user,
  }) async {
    return _postMark('/api/v1/flutter/marks', id: id, type: type, user: user);
  }

  /// 取消不友好标记。
  Future<LatestMarkResult> cancelMark({
    required int id,
    required String type,
    required String user,
  }) async {
    return _postMark(
        '/api/v1/flutter/marks/cancel', id: id, type: type, user: user);
  }

  Future<LatestMarkResult> _postMark(
    String path, {
    required int id,
    required String type,
    required String user,
  }) async {
    final uri = Uri.https(AppConfig.latestMfunsHost, path);
    try {
      final request = await _httpClient.postUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.contentTypeHeader,
          ContentType.json.toString());
      request.headers.set(HttpHeaders.userAgentHeader, AppConfig.userAgent);
      request.add(
          utf8.encode(jsonEncode({'id': id, 'type': type, 'user': user})));
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _LatestHttpException(
          response.statusCode,
          _markErrorDetail(body, response.statusCode),
        );
      }
      final decoded = jsonDecode(body);
      final root = _asMap(decoded);
      if (_asInt(root['code']) != 1) {
        throw LatestMfunsException('${root['msg'] ?? '操作失败'}');
      }
      final data = _asMap(root['data']);
      return LatestMarkResult(
        markCount: _asInt(data['mark_count']) ?? 0,
        blocked: data['blocked'] == true,
      );
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

  /// 4xx 错误优先展示服务端 detail，登录失效单独提示。
  String _markErrorDetail(String body, int statusCode) {
    if (statusCode == 401) {
      return '登录状态已失效，请重新登录后再操作';
    }
    try {
      final decoded = jsonDecode(body);
      final detail = _asMap(decoded)['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    } on FormatException {
      // 忽略非 JSON 错误体，使用默认提示。
    }
    return '标记服务请求失败（$statusCode）';
  }

  Future<Object?> _getJson(
    String path, {
    required double? before,
    required int limit,
    String user = '',
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (before != null) query['before'] = '$before';
    if (user.isNotEmpty) query['user'] = user;
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

  @override
  String toString() => message;
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
