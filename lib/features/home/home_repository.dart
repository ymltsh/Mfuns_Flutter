import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import '../../core/network/mfuns_api_client.dart';

class ContentPreview {
  const ContentPreview({
    required this.id,
    required this.title,
    required this.summary,
    required this.cover,
    required this.author,
    required this.category,
    required this.type,
    required this.likes,
    required this.comments,
    required this.views,
    this.authorId,
    this.authorAvatar = '',
    this.createdAt,
  });

  final int id;
  final String title;
  final String summary;
  final String cover;
  final String author;
  final String category;
  final int type;
  final int likes;
  final int comments;
  final int views;
  final int? authorId;
  final String authorAvatar;
  final DateTime? createdAt;

  bool get isVideo => type == 1;

  factory ContentPreview.fromJson(Map<String, dynamic> json) {
    final resource = _asMap(json['resource_info']);
    final source = resource.isEmpty ? json : {...json, ...resource};
    final user = _asMap(source['user']);
    final category = _asMap(source['category']);
    return ContentPreview(
      id: _asInt(source['id'] ?? source['resource_id']) ?? 0,
      title: '${source['title'] ?? '未命名内容'}',
      summary: '${source['summary'] ?? source['content'] ?? ''}',
      cover: _coverUrl(source['cover']),
      author:
          '${user['name'] ?? user['username'] ?? source['user_name'] ?? ''}',
      authorId: _asInt(user['id'] ?? user['user_id'] ?? source['user_id']),
      authorAvatar: _coverUrl(user['avatar'] ?? user['face']),
      category:
          '${category['name'] ?? source['category_name'] ?? source['tag'] ?? ''}',
      type: _asResourceType(source['type'] ?? source['resource_type']),
      likes: _asInt(source['like_count']) ?? 0,
      comments: _asInt(source['comment_count']) ?? 0,
      views: _asInt(source['view_count']) ?? 0,
      createdAt: _asDateTime(
          source['created_at'] ?? source['time'] ?? source['createdAt']),
    );
  }
}

/// A community post from `/v1/feeds/list` or `/v1/feeds/new_reply_list`.
///
/// Feed records are not article/video resources: treating them as a
/// [ContentPreview] made taps resolve to the article endpoint. Keep the
/// timeline model separate so its content and cursor can evolve independently.
class TimelineFeed {
  const TimelineFeed({
    required this.id,
    required this.author,
    required this.authorId,
    required this.avatar,
    required this.content,
    required this.spans,
    required this.createdAt,
    required this.likes,
    required this.comments,
    required this.views,
    required this.images,
    required this.resource,
    this.isAutoSync = false,
  });

  final int id;
  final String author;
  final int? authorId;
  final String avatar;
  final String content;
  final List<CommentSpan> spans;
  final DateTime? createdAt;
  final int likes;
  final int comments;
  final int views;
  final List<String> images;
  final ContentPreview? resource;

  /// 发送文章/视频时自动生成的同步动态：Web 端 /feed/{id} 会 302 跳转到
  /// 对应内容页，App 端点击应直接打开文章/视频页。
  final bool isAutoSync;

  factory TimelineFeed.fromJson(Map<String, dynamic> json) {
    final source = _asMap(json['feed']).isEmpty
        ? json
        : {...json, ..._asMap(json['feed'])};
    final user = _asMap(source['user'] ?? source['user_info']);
    final extra = _asMap(source['extra']);
    final resource = _asMap(extra['resource']);
    final autoSync =
        source['is_auto_sync'] == true || source['is_auto_sync'] == 1;
    final like = _asMap(_asMap(source['like_status'])['like']);
    final rawContent =
        '${source['content'] ?? source['text'] ?? source['summary'] ?? resource['summary'] ?? resource['title'] ?? ''}';
    return TimelineFeed(
      id: _asInt(source['id'] ?? source['feed_id']) ?? 0,
      author:
          '${user['name'] ?? user['username'] ?? source['user_name'] ?? source['author'] ?? ''}',
      authorId: _asInt(user['id'] ??
          user['user_id'] ??
          source['user_id'] ??
          source['author_id']),
      avatar: _coverUrl(user['avatar'] ??
          user['face'] ??
          source['avatar'] ??
          source['user_avatar']),
      content: _toPlainText(rawContent),
      spans: _commentSpans(rawContent),
      createdAt: _asDateTime(
          source['created_at'] ?? source['time'] ?? source['createdAt']),
      likes: _asInt(source['like_count'] ??
              source['likes'] ??
              like['count'] ??
              resource['like_count']) ??
          0,
      comments: _asInt(source['comment_count'] ??
              source['comments'] ??
              resource['comment_count']) ??
          0,
      views: _asInt(source['view_count'] ??
              source['views'] ??
              resource['view_count']) ??
          0,
      images: _feedImages(source['images'] ??
          source['image_list'] ??
          source['pictures'] ??
          extra['images']),
      resource: _feedResource(source, user, autoSync),
      isAutoSync: autoSync,
    );
  }
}

/// 动态引用的内容：优先取 `extra.resource`（普通分享动态）；自动同步动态
/// （is_auto_sync）没有 extra.resource，用顶层 resource_id / resource_type
/// 构造文章/视频预览，与 Web 端 302 跳转到内容页的行为一致。
ContentPreview? _feedResource(
  Map<String, dynamic> source,
  Map<String, dynamic> user,
  bool autoSync,
) {
  final extraResource = _asMap(_asMap(source['extra'])['resource']);
  if (extraResource.isNotEmpty) {
    return ContentPreview.fromJson(extraResource);
  }
  if (!autoSync) return null;
  final resourceId = _asInt(source['resource_id']);
  final resourceType = _asInt(source['resource_type']);
  if (resourceId == null || resourceType == null || resourceId <= 0) {
    return null;
  }
  return ContentPreview(
    id: resourceId,
    title: '${source['title'] ?? ''}',
    summary: _toPlainText('${source['content'] ?? ''}'),
    cover: _coverUrl(source['cover']),
    author:
        '${user['name'] ?? user['username'] ?? source['user_name'] ?? ''}',
    category: '',
    type: resourceType,
    likes: _asInt(source['like_count']) ?? 0,
    comments: _asInt(source['comment_count']) ?? 0,
    views: _asInt(source['view_count']) ?? 0,
    authorId: _asInt(user['id'] ?? user['user_id']),
    authorAvatar: _coverUrl(user['avatar'] ?? user['face']),
  );
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.avatarFrame,
    required this.banner,
    required this.bio,
    required this.gender,
    required this.level,
    required this.exp,
    required this.fans,
    required this.follows,
    required this.totalLikes,
  });

  final int id;
  final String name;
  final String avatar;
  final String avatarFrame;
  final String banner;
  final String bio;
  final String gender;
  final int? level;
  final int? exp;
  final int fans;
  final int follows;
  final int totalLikes;

  UserProfile copyWith({int? fans, int? follows}) => UserProfile(
        id: id,
        name: name,
        avatar: avatar,
        avatarFrame: avatarFrame,
        banner: banner,
        bio: bio,
        gender: gender,
        level: level,
        exp: exp,
        fans: fans ?? this.fans,
        follows: follows ?? this.follows,
        totalLikes: totalLikes,
      );

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final source = _asMap(json['user']).isEmpty ? json : _asMap(json['user']);
    final rawInfo = source['info'];
    final info = _asMap(rawInfo);
    final frame = _asMap(source['avatar_frame']);
    return UserProfile(
      id: _asInt(source['id'] ?? source['user_id']) ?? 0,
      name: '${source['name'] ?? source['username'] ?? 'Mfuns 用户'}',
      avatar: _coverUrl(source['avatar'] ?? source['face']),
      avatarFrame: _coverUrl(frame['image'] ?? source['avatar_frame']),
      banner: _coverUrl(source['banner_image'] ?? source['banner']),
      bio: _toPlainText(
          '${source['bio'] ?? source['signature'] ?? (rawInfo is String ? rawInfo : '')}'),
      gender: '${source['gender'] ?? info['gender'] ?? ''}',
      level: _asInt(source['level_id'] ?? info['level_id']) ??
          _levelFromBadges(source['badges']),
      exp: _asInt(source['exp'] ?? source['experience'] ?? info['exp']),
      fans: _asInt(source['fans'] ?? source['fans_count'] ?? info['fans']) ?? 0,
      follows: _asInt(source['follows'] ??
              source['follow_count'] ??
              source['following'] ??
              info['follows']) ??
          0,
      totalLikes:
          _asInt(source['total_likes_count'] ?? info['total_likes_count']) ?? 0,
    );
  }
}

class CategoryNode {
  const CategoryNode({required this.id, required this.name, this.parentId});

  final int id;
  final String name;
  final int? parentId;

  factory CategoryNode.fromJson(Map<String, dynamic> json) => CategoryNode(
        id: _asInt(json['id']) ?? 0,
        name: '${json['name'] ?? ''}',
        parentId: _asInt(json['parent_id']),
      );
}

/// 签到信息（`/v1/sign/sign_list`）：本月已签到日期与累计次数。
class SignInfo {
  const SignInfo({
    required this.signedDays,
    required this.monthTimes,
    required this.allTimes,
  });

  final List<int> signedDays;
  final int monthTimes;
  final int allTimes;

  factory SignInfo.fromJson(Map<String, dynamic> json) => SignInfo(
        signedDays: _signDays(json['list']),
        monthTimes: _asInt(json['month_times']) ?? 0,
        allTimes: _asInt(json['all_times']) ?? 0,
      );
}

/// 今日签到排行榜条目（`/v1/sign/sign_rank_today`）。
class SignRankEntry {
  const SignRankEntry({
    required this.userId,
    required this.name,
    required this.avatar,
    required this.nameColor,
    required this.count,
    required this.signedAt,
  });

  final int userId;
  final String name;
  final String avatar;
  final String nameColor;
  final int count;
  final DateTime? signedAt;

  factory SignRankEntry.fromJson(Map<String, dynamic> json) {
    final user = _asMap(json['user']);
    return SignRankEntry(
      userId: _asInt(user['id'] ?? user['user_id']) ?? 0,
      name: '${user['name'] ?? user['username'] ?? 'Mfuns 用户'}',
      avatar: _coverUrl(user['avatar'] ?? user['face']),
      nameColor: '${user['name_color'] ?? ''}',
      count: _asInt(json['count']) ?? 0,
      signedAt: _asDateTime(json['time']),
    );
  }
}

/// 累计签到奖励（`/v1/sign/accumulated_awards`）。
class SignAward {
  const SignAward({required this.desc, required this.type});

  final String desc;
  final String type;

  factory SignAward.fromJson(Map<String, dynamic> json) => SignAward(
        desc: '${json['desc'] ?? ''}',
        type: '${json['type'] ?? ''}',
      );
}

/// 一页浏览历史：条目与下一页游标（最后一条的 time，null 表示无更多）。
class HistoryPage {
  const HistoryPage({required this.items, this.nextStartTime});

  final List<ContentPreview> items;
  final double? nextStartTime;
}

/// 用户背包道具（`/v1/user/get_user_backpack`）：改名卡、补签卡等。
class BackpackItem {
  const BackpackItem({
    required this.id,
    required this.name,
    required this.tag,
    required this.description,
    required this.icon,
    required this.count,
  });

  final int id;
  final String name;
  final String tag;
  final String description;
  final String icon;
  final int count;

  factory BackpackItem.fromJson(Map<String, dynamic> json) => BackpackItem(
        id: _asInt(json['id']) ?? 0,
        name: '${json['name'] ?? ''}',
        tag: '${json['tag'] ?? ''}',
        description: '${json['description'] ?? ''}',
        icon: _coverUrl(json['icon']),
        count: _asInt(json['count']) ?? 0,
      );
}

/// 等级经验区间（`/v1/user/level_section`）：达到该等级所需经验。
class LevelSection {
  const LevelSection({required this.levelId, required this.experience});

  final int levelId;
  final int experience;

  factory LevelSection.fromJson(Map<String, dynamic> json) => LevelSection(
        levelId: _asInt(json['level_id'] ?? json['id']) ?? 0,
        experience: _asInt(json['experience']) ?? 0,
      );
}

/// Credentials + target for a VOD upload (`/v1/contribute/video/get_upload_auth`).
class VideoUploadAuth {
  const VideoUploadAuth({
    required this.videoId,
    required this.accessKeyId,
    required this.accessKeySecret,
    required this.securityToken,
    required this.endpoint,
    required this.bucket,
    required this.objectKey,
  });

  final String videoId;
  final String accessKeyId;
  final String accessKeySecret;
  final String securityToken;
  final String endpoint;
  final String bucket;
  final String objectKey;

  factory VideoUploadAuth.fromJson(Map<String, dynamic> json) {
    final auth = jsonDecode(
        utf8.decode(base64.decode('${json['UploadAuth']}'.trim())));
    final address = jsonDecode(
        utf8.decode(base64.decode('${json['UploadAddress']}'.trim())));
    final authMap = auth is Map<String, dynamic> ? auth : const {};
    final addressMap = address is Map<String, dynamic> ? address : const {};
    var endpoint = '${addressMap['Endpoint'] ?? ''}';
    if (endpoint.startsWith('http://')) {
      endpoint = endpoint.substring('http://'.length);
    } else if (endpoint.startsWith('https://')) {
      endpoint = endpoint.substring('https://'.length);
    }
    return VideoUploadAuth(
      videoId: '${json['VideoId'] ?? ''}',
      accessKeyId: '${authMap['AccessKeyId'] ?? ''}',
      accessKeySecret: '${authMap['AccessKeySecret'] ?? ''}',
      securityToken: '${authMap['SecurityToken'] ?? ''}',
      endpoint: endpoint,
      bucket: '${addressMap['Bucket'] ?? ''}',
      objectKey: '${addressMap['FileName'] ?? addressMap['ObjectName'] ?? ''}',
    );
  }
}

/// A submission (投稿) from `/v1/contribute/list`.
class SubmissionItem {
  const SubmissionItem({
    required this.id,
    required this.resourceId,
    required this.title,
    required this.status,
    required this.createdAt,
  });

  final int id;
  final int? resourceId;
  final String title;
  final int status;
  final DateTime? createdAt;

  String get statusLabel => submissionStatusLabel(status);

  factory SubmissionItem.fromJson(Map<String, dynamic> json) => SubmissionItem(
        id: _asInt(json['id']) ?? 0,
        resourceId: _asInt(json['resource_id']),
        title: '${json['title'] ?? ''}',
        status: _asInt(json['status']) ?? 0,
        createdAt: _asDateTime(json['created_at']),
      );
}

/// Submission detail from `/v1/contribute/get`.
class SubmissionDetail {
  const SubmissionDetail({
    required this.id,
    required this.resourceId,
    required this.title,
    required this.content,
    required this.status,
    required this.categoryId,
    required this.tags,
    required this.cover,
  });

  final int id;
  final int? resourceId;
  final String title;
  final String content;
  final int status;
  final int? categoryId;
  final List<String> tags;
  final String cover;

  String get statusLabel => submissionStatusLabel(status);

  factory SubmissionDetail.fromJson(Map<String, dynamic> json) {
    final source = _asMap(json['contribute']).isEmpty
        ? json
        : _asMap(json['contribute']);
    return SubmissionDetail(
      id: _asInt(source['id']) ?? 0,
      resourceId: _asInt(source['resource_id']),
      title: '${source['title'] ?? ''}',
      content: _toPlainText(
          '${source['content'] ?? source['summary'] ?? ''}'),
      status: _asInt(source['status']) ?? 0,
      categoryId: _asInt(source['category_id'] ?? source['cid']),
      tags: _toTags(source['tags']),
      cover: _coverUrl(source['cover']),
    );
  }
}

String submissionStatusLabel(int status) => switch (status) {
      0 => '草稿',
      1 => '已发布',
      2 => '审核中',
      3 => '驳回',
      4 => '被驳回修改',
      5 => '定时发布',
      _ => '状态 $status',
    };

/// One page of favorite-folder items with the next cursor to request.
class FavoriteItemsPage {
  const FavoriteItemsPage({required this.items, this.nextLastId});

  final List<ContentPreview> items;

  /// Cursor for the next page; null means there is no more content.
  final int? nextLastId;
}

class FavoriteFolder {
  const FavoriteFolder({
    required this.id,
    required this.name,
    required this.description,
    required this.count,
  });

  final int id;
  final String name;
  final String description;
  final int count;

  factory FavoriteFolder.fromJson(Map<String, dynamic> json) => FavoriteFolder(
        id: _asInt(json['id']) ?? 0,
        name: '${json['name'] ?? '未命名收藏夹'}',
        description: '${json['desc'] ?? ''}',
        count: _asInt(json['count']) ?? 0,
      );
}

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.userId,
    required this.authorName,
    required this.avatar,
    required this.content,
    required this.spans,
    required this.images,
    required this.likes,
    required this.liked,
    required this.replyCount,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final String authorName;
  final String avatar;
  final String content;
  final List<CommentSpan> spans;
  final List<String> images;
  final int likes;
  final bool liked;
  final int replyCount;
  final DateTime? createdAt;

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    final user = _asMap(json['user']).isEmpty
        ? _asMap(json['user_info'])
        : _asMap(json['user']);
    final spans = _commentSpans('${json['content'] ?? ''}');
    final ext = _asMap(json['content_ext']);
    final like = _asMap(_asMap(json['like_status'])['like']);
    return CommunityComment(
      id: _asInt(json['id']) ?? 0,
      userId: _asInt(json['user_id']) ??
          _asInt(user['id'] ?? user['user_id']) ??
          0,
      authorName:
          '${user['name'] ?? user['username'] ?? user['nickname'] ?? json['user_name'] ?? json['nickname'] ?? ''}',
      avatar: _coverUrl(user['avatar'] ??
          user['face'] ??
          user['user_avatar'] ??
          json['avatar'] ??
          json['user_avatar']),
      content: spans
          .where((span) => !span.isSticker)
          .map((span) => span.isMention ? '@${span.mentionName}' : span.text)
          .join()
          .trim(),
      spans: spans,
      images: _feedImages(ext['images'] ?? json['images']),
      likes: _asInt(like['count']) ?? _asInt(json['like_count']) ?? 0,
      liked: like['is_active'] == true || like['is_active'] == 1,
      replyCount: _asInt(json['reply_count']) ?? 0,
      createdAt: _asDateTime(json['created_at']),
    );
  }
}

/// One piece of a comment: plain text, a private-pack sticker, or a user
/// mention.
///
/// Stickers are encoded by Mfuns as Quill inserts of the form
/// `{"insert": {"sticker": "s-1"}}` where the key is `<pack>-<id>`; mentions
/// are `{"insert": {"mention": {"id": "38461", "value": "少女乌斯"}}}`.
class CommentSpan {
  const CommentSpan.text(this.text)
      : stickerKey = '',
        mentionId = '',
        mentionName = '';
  const CommentSpan.sticker(this.stickerKey)
      : text = '',
        mentionId = '',
        mentionName = '';
  const CommentSpan.mention(this.mentionId, this.mentionName)
      : text = '',
        stickerKey = '';

  final String text;
  final String stickerKey;
  final String mentionId;
  final String mentionName;

  bool get isSticker => stickerKey.isNotEmpty;
  bool get isMention => mentionName.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is CommentSpan &&
      other.text == text &&
      other.stickerKey == stickerKey &&
      other.mentionId == mentionId &&
      other.mentionName == mentionName;

  @override
  int get hashCode => Object.hash(text, stickerKey, mentionId, mentionName);
}

List<CommentSpan> _commentSpans(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return const [];
  if (value.startsWith('{')) {
    try {
      final decoded = jsonDecode(value);
      final ops = _asMap(decoded)['ops'];
      if (ops is List) {
        final spans = <CommentSpan>[];
        for (final op in ops.whereType<Map<String, dynamic>>()) {
          final insert = op['insert'];
          if (insert is String) {
            final text = insert.trimRight();
            if (text.isNotEmpty) {
              spans.add(CommentSpan.text(text));
            }
          } else if (insert is Map<String, dynamic>) {
            final mention = insert['mention'];
            if (mention is Map<String, dynamic>) {
              final id = '${mention['id'] ?? ''}';
              final value = '${mention['value'] ?? ''}';
              if (value.isNotEmpty) {
                spans.add(CommentSpan.mention(id, value));
              }
            }
            final sticker = insert['sticker'];
            if (sticker is String && sticker.isNotEmpty) {
              spans.add(CommentSpan.sticker(sticker));
            }
          }
        }
        return spans;
      }
    } on FormatException {
      // Fall back to the HTML/text normalization below.
    }
  }
  return _htmlSpans(value);
}

/// Comment bodies come back as HTML when `html=1`: stickers are
/// `<img class='sticker' src='.../s/1.png' alt='[s-1]'/>`. Split those out
/// so they can be rendered as images instead of being stripped as tags.
List<CommentSpan> _htmlSpans(String html) {
  const stickerPattern =
      "<img[^>]*class=['\"][^'\"]*sticker[^'\"]*['\"][^>]*>";
  final spans = <CommentSpan>[];
  var cursor = 0;
  for (final match in RegExp(stickerPattern, caseSensitive: false).allMatches(html)) {
    final before = _htmlToText(html.substring(cursor, match.start));
    cursor = match.end;
    if (before.isNotEmpty) spans.add(CommentSpan.text(before));
    final tag = match.group(0) ?? '';
    final alt = RegExp("alt=['\"]([^'\"]+)['\"]", caseSensitive: false)
        .firstMatch(tag)
        ?.group(1);
    final src = RegExp("src=['\"]([^'\"]+)['\"]", caseSensitive: false)
        .firstMatch(tag)
        ?.group(1);
    final key = _stickerKey(alt, src);
    spans.add(CommentSpan.sticker(key));
  }
  final tail = _htmlToText(html.substring(cursor));
  if (tail.isNotEmpty) spans.add(CommentSpan.text(tail));
  return spans.isEmpty ? [CommentSpan.text(_htmlToText(html))] : spans;
}

String _stickerKey(String? alt, String? src) {
  if (alt != null) {
    final trimmed = alt.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      final key = trimmed.substring(1, trimmed.length - 1).trim();
      if (key.isNotEmpty) return key;
    }
  }
  if (src == null) return '';
  final segments = Uri.tryParse(src)?.pathSegments ?? const <String>[];
  if (segments.length < 2) return '';
  final id = segments.last.replaceAll(RegExp(r'\.[^.]+$'), '');
  return '${segments[segments.length - 2]}-$id';
}

/// Strips tags and decodes HTML entities (`&amp;`/`&#039;`/`&lt;` …) so
/// comment and feed text reads naturally. Only fed through the html parser
/// when an entity is actually present, so plain text stays untouched.
String _htmlToText(String raw) {
  final withoutTags = raw.replaceAll(RegExp(r'<[^>]*>'), ' ');
  final collapsed = withoutTags.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty || !collapsed.contains('&')) return collapsed;
  try {
    return html_parser.parseFragment(collapsed).text?.trim() ?? collapsed;
  } on FormatException {
    return collapsed;
  }
}

/// Converts plain text containing `[pack-id]` sticker markers (the format
/// used in the official editor's alt tags) into spans so markers become
/// real stickers when the comment is posted. `[@用户名]` / `[@id:用户名]`
/// markers become user mentions. Unmarked text stays as text.
List<CommentSpan> commentSpansFromText(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  final spans = <CommentSpan>[];
  final pattern = RegExp(r'\[@(\d*):?([^\]]+)\]|\[([A-Za-z]+-\d+)\]');
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    final before = text.substring(cursor, match.start);
    cursor = match.end;
    if (before.isNotEmpty) spans.add(CommentSpan.text(before));
    final mentionId = match.group(1);
    if (mentionId != null) {
      spans.add(CommentSpan.mention(mentionId, match.group(2)!));
    } else {
      final key = match.group(3);
      if (key != null && key.isNotEmpty) {
        spans.add(CommentSpan.sticker(key));
      }
    }
  }
  final tail = text.substring(cursor);
  if (tail.isNotEmpty) spans.add(CommentSpan.text(tail));
  return spans;
}

String commentQuillJson(List<CommentSpan> spans) =>
    _buildQuillJson(spans, const []);

/// 私信用：把文本/表情 spans 与图片一起编码为 Quill JSON。图片以
/// `{"insert":{"image":"path"}}` 内嵌在内容中（与接收端解析一致）。
String messageQuillJson(List<CommentSpan> spans, List<String> images) =>
    _buildQuillJson(spans, images);

String _buildQuillJson(List<CommentSpan> spans, List<String> images) {
  final ops = <Map<String, Object?>>[];
  for (final span in spans) {
    if (span.isMention) {
      ops.add({
        'insert': {
          'mention': {'id': span.mentionId, 'value': span.mentionName}
        }
      });
      continue;
    }
    if (span.isSticker) {
      ops.add({'insert': {'sticker': span.stickerKey}});
      continue;
    }
    final lines = span.text.split('\n');
    for (final line in lines) {
      ops.add({'insert': '$line\n'});
    }
  }
  for (final image in images) {
    ops.add({'insert': {'image': image}});
  }
  if (ops.isEmpty || ops.last['insert'] is! String) {
    ops.add({'insert': '\n'});
  }
  return jsonEncode({'ops': ops});
}

class MessageConversation {
  const MessageConversation({
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.lastMessage,
    required this.unread,
    required this.lastTime,
  });

  final int userId;
  final String userName;
  final String userAvatar;
  final String lastMessage;
  final int unread;
  final DateTime? lastTime;

  factory MessageConversation.fromJson(Map<String, dynamic> json) {
    final user = _asMap(json['user']);
    final last = _asMap(_asMap(json['last_msg'] ?? json['last_message'])['data']);
    final lastRaw = '${last['message'] ?? last['msg'] ?? ''}';
    var lastMessage = _quillToText(lastRaw);
    if (lastMessage.isEmpty &&
        _uniqueImages([
          ..._feedImages(last['images'] ?? '[]'),
          ..._contentImages(lastRaw),
        ]).isNotEmpty) {
      lastMessage = '[图片]';
    }
    return MessageConversation(
      userId: _asInt(user['id'] ?? user['user_id'] ?? json['user_id']) ?? 0,
      userName:
          '${user['name'] ?? user['username'] ?? '用户 ${json['user_id']}'}',
      userAvatar: _coverUrl(user['avatar'] ?? user['face']),
      lastMessage: lastMessage,
      unread: _asInt(json['no_read'] ?? json['unread']) ?? 0,
      lastTime:
          _asDateTime(last['time'] ?? json['updated_at'] ?? json['time']),
    );
  }
}

class MessageRecord {
  const MessageRecord({
    required this.uid,
    required this.message,
    required this.spans,
    required this.images,
    required this.time,
  });

  final int uid;
  final String message;
  final List<CommentSpan> spans;
  final List<String> images;
  final DateTime? time;

  factory MessageRecord.fromJson(Map<String, dynamic> json) {
    final data = _asMap(json['data']);
    final raw = '${data['message'] ?? data['msg'] ?? ''}';
    return MessageRecord(
      uid: _asInt(json['uid'] ?? data['uid'] ?? data['user_id']) ?? 0,
      message: _quillToText(raw),
      spans: _commentSpans(raw),
      images: _uniqueImages([
        ..._feedImages(data['images'] ?? json['images'] ?? '[]'),
        ..._contentImages(raw),
      ]),
      time: _asDateTime(data['time'] ?? json['created_at']),
    );
  }
}

class NotifyCounts {
  const NotifyCounts({
    required this.like,
    required this.comment,
    required this.mention,
    required this.system,
    this.message = 0,
  });

  final int like;
  final int comment;
  final int mention;
  final int system;

  /// 私信未读数（/v1/notify/count 返回的 message 字段，与通知同一来源）。
  final int message;

  factory NotifyCounts.fromJson(Map<String, dynamic> json) => NotifyCounts(
        like: _asInt(json['like']) ?? 0,
        comment: _asInt(json['comment']) ?? 0,
        mention: _asInt(json['mention']) ?? 0,
        system: _asInt(json['system']) ?? 0,
        message: _asInt(json['message']) ?? 0,
      );
}

class NotifyItem {
  const NotifyItem({
    required this.senderUserId,
    required this.senderName,
    required this.senderAvatar,
    required this.createdAt,
    required this.text,
    required this.commentId,
    required this.areaId,
    required this.resourceId,
    required this.resourceType,
  });

  final int senderUserId;
  final String senderName;
  final String senderAvatar;
  final DateTime? createdAt;

  /// 通知正文：优先取新收到的评论内容（`reply_text`），
  /// 缺失时回退到 `text`（被评论的父内容）。
  final String text;
  final int? commentId;

  /// Comment area id, when the notification payload carries it.
  final int? areaId;

  /// The referenced content (article/video/feed) and its resource type
  /// (0=article, 1=video, 4=feed/comment area).
  final int? resourceId;
  final int? resourceType;

  factory NotifyItem.fromJson(Map<String, dynamic> json) {
    final params = _asMap(json['notify_params'] ?? json['params']);
    final sender = _asMap(json['sender'] ?? json['user'] ?? json['user_info']);
    final resource = _asMap(params['resource']);
    return NotifyItem(
      senderUserId: _asInt(
              json['sender_user_id'] ?? sender['id'] ?? sender['user_id']) ??
          0,
      senderName: '${sender['name'] ?? sender['username'] ?? ''}',
      senderAvatar: _coverUrl(sender['avatar'] ?? sender['face']),
      createdAt: _asDateTime(json['created_at'] ?? json['time']),
      text: _quillToText(
          '${params['reply_text'] ?? params['text'] ?? params['content'] ?? ''}'),
      commentId: _asInt(params['comment_id']),
      areaId: _asInt(params['area_id'] ?? json['area_id']),
      resourceId: _asInt(params['resource_id'] ??
          params['resourceId'] ??
          json['resource_id'] ??
          resource['id'] ??
          resource['resource_id'] ??
          json['content_id']),
      resourceType: _asInt(params['resource_type'] ??
              params['resourceType'] ??
              json['resource_type'] ??
              resource['type'] ??
              resource['resource_type'] ??
              json['content_type']) ??
          _resourceTypeFromText(
              '${params['resource_type'] ?? resource['type']}'),
    );
  }
}

class DanmakuItem {
  const DanmakuItem({
    required this.time,
    required this.type,
    required this.color,
    required this.content,
    required this.size,
  });

  final Duration time;
  final int type;
  final int color;
  final String content;
  final int size;

  factory DanmakuItem.fromJson(Object? value) {
    if (value is! List) {
      return const DanmakuItem(
        time: Duration.zero,
        type: 1,
        color: 0xffffff,
        content: '',
        size: 25,
      );
    }
    final seconds = value.isNotEmpty ? _asDouble(value[0]) ?? 0 : 0;
    return DanmakuItem(
      time: Duration(milliseconds: (seconds * 1000).round()),
      type: value.length > 1 ? _asInt(value[1]) ?? 1 : 1,
      color: value.length > 2 ? _asInt(value[2]) ?? 0xffffff : 0xffffff,
      content: value.length > 4 ? '${value[4]}' : '',
      size: value.length > 5 ? _asInt(value[5]) ?? 25 : 25,
    );
  }
}

class ContentDetail {
  const ContentDetail({
    required this.preview,
    required this.content,
    required this.rawContent,
    required this.tags,
    required this.commentAreaId,
  });

  final ContentPreview preview;

  /// Plain-text excerpt for compact surfaces such as a video information row.
  final String content;

  /// Untouched server body, used by the rich article renderer.
  final String rawContent;
  final List<String> tags;
  final int? commentAreaId;
}

class FeedDetail {
  const FeedDetail({
    required this.feed,
    required this.rawContent,
    required this.tags,
    required this.commentAreaId,
  });

  final TimelineFeed feed;
  final String rawContent;
  final List<String> tags;
  final int? commentAreaId;
}

class VideoQuality {
  const VideoQuality({
    required this.part,
    required this.name,
    required this.label,
    required this.url,
  });

  final int part;
  final String name;
  final String label;
  final String url;
}

class ResourceReactionStatus {
  const ResourceReactionStatus({
    required this.liked,
    required this.disliked,
    required this.likes,
    required this.dislikes,
  });

  final bool liked;
  final bool disliked;
  final int likes;
  final int dislikes;
}

class HomeRepository {
  const HomeRepository(this._client);

  final MfunsApiClient _client;

  Future<List<ContentPreview>> getRecommendations() async {
    final response = await _client.get(
      '/v1/recommend/get',
      // The mobile home route requests ten mixed recommendations initially.
      query: const {'category': -1, 'size': 10},
    );
    return _toPreviewList(response.data);
  }

  Future<List<ContentPreview>> search(String text, {int type = -1}) async {
    final response = await _client.get(
      '/v1/search/resource',
      query: {
        'text': text,
        'type': type,
        'page': 1,
        'size': 20,
        // The mobile site currently requires this even though older docs mark it optional.
        'sort': 'all',
      },
    );
    return _toPreviewList(response.data);
  }

  Future<List<ContentPreview>> getHotRankings() async {
    final response = await _client.get('/v1/leaderboards/hot');
    return _toPreviewList(response.data);
  }

  /// 搜索用户（@ 提及用）：`GET /v1/search/user`。
  Future<List<UserProfile>> searchUsers(
    String keyword, {
    int page = 1,
    int size = 10,
  }) async {
    final response = await _client.get(
      '/v1/search/user',
      query: {'user': keyword, 'page': page, 'size': size},
    );
    final root = _asMap(response.data);
    final rawList = response.data is List ? response.data : root['list'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(UserProfile.fromJson)
        .where((user) => user.id != 0)
        .toList(growable: false);
  }

  Future<List<CategoryNode>> getCategories() async {
    final response = await _client.get('/v1/category/all');
    final categories = <CategoryNode>[];
    _collectCategories(response.data, categories);
    final unique = <int, CategoryNode>{
      for (final category in categories)
        if (category.id != 0 && category.name.isNotEmpty) category.id: category,
    };
    return unique.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<List<ContentPreview>> getCategoryContents(int categoryId) async {
    final response = await _client.get(
      // Category chips on the mobile home page are a filtered recommendation
      // request, not the legacy category/list resource feed.
      '/v1/recommend/get',
      query: {'category': categoryId, 'size': 20},
    );
    return _toPreviewList(response.data);
  }

  /// 按标签获取文章列表：`GET /v1/tag/article_list?tag=xxx`。
  Future<List<ContentPreview>> getTagArticles(String tag) async {
    final response = await _client.get(
      '/v1/tag/article_list',
      query: {'tag': tag},
    );
    return _toPreviewList(response.data);
  }

  Future<List<TimelineFeed>> getFeeds({
    required int startId,
    required bool following,
    int? userId,
  }) async {
    final response = await _client.get(
      '/v1/feeds/list',
      query: {
        'start_id': startId,
        'html': 1,
        if (following) 'follow': 1,
        if (userId != null) 'user_id': userId,
      },
    );
    return _toTimelineFeeds(response.data);
  }

  /// The mobile `/timeline` route uses this page-numbered feed, rather than
  /// the cursor-based `/feeds/list` endpoint used for a user's follow stream.
  Future<List<TimelineFeed>> getTimelineFeeds({
    required int page,
    int size = 20,
  }) async {
    final response = await _client.get(
      '/v1/feeds/new_reply_list',
      query: {'page': page, 'size': size, 'html': 1},
    );
    return _toTimelineFeeds(response.data);
  }

  Future<FeedDetail> getFeedDetail(int feedId) async {
    final response = await _client.get(
      '/v1/feeds/get',
      query: {'id': feedId, 'html': 1},
    );
    final source = _asMap(response.data);
    return FeedDetail(
      feed: TimelineFeed.fromJson(source),
      rawContent: '${source['content'] ?? ''}',
      tags: _toTags(source['tags']),
      commentAreaId: _asInt(source['comment_area_id']),
    );
  }

  Future<UserProfile> getUserProfile(int userId) async {
    final responses = await Future.wait([
      _client.get('/v1/user/get_user', query: {'id': userId}),
      _client.get('/v1/follow/count', query: {'user_id': userId}),
    ]);
    final profile = UserProfile.fromJson(_asMap(responses[0].data));
    final counts = _asMap(responses[1].data);
    return profile.copyWith(
      follows: _asInt(counts['follow']) ?? profile.follows,
      fans: _asInt(counts['fans']) ?? profile.fans,
    );
  }

  /// 每日签到（需登录），成功返回服务端消息（如"签到成功"）。
  Future<String> sign() async {
    final response = await _client.get('/v1/sign/sign');
    return response.message;
  }

  /// 签到信息：本月已签到日期与累计次数（需登录）。
  Future<SignInfo> signList() async {
    final response = await _client.get('/v1/sign/sign_list');
    return SignInfo.fromJson(_asMap(response.data));
  }

  /// 补签指定日期（需登录，消耗补签卡）。
  Future<void> signAgain(int day) async {
    await _client.postJson('/v1/sign/sign_again', {'day': day});
  }

  /// 今日签到排行榜（公开）。
  Future<List<SignRankEntry>> signRankToday() async {
    final response = await _client.get('/v1/sign/sign_rank_today');
    final raw = response.data;
    final list = raw is List ? raw : _asMap(raw)['list'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(SignRankEntry.fromJson)
        .where((entry) => entry.userId != 0)
        .toList(growable: false);
  }

  /// 等级经验区间表（公开）：每个等级达到所需经验，按等级升序。
  Future<List<LevelSection>> getLevelSections() async {
    final response = await _client.get('/v1/user/level_section');
    final raw = response.data;
    final list = raw is List ? raw : _asMap(raw)['list'];
    if (list is! List) return const [];
    final sections = <int, LevelSection>{};
    for (final entry in list.whereType<Map<String, dynamic>>()) {
      final section = LevelSection.fromJson(entry);
      if (section.levelId > 0) sections[section.levelId] = section;
    }
    return sections.values.toList(growable: false)
      ..sort((a, b) => a.levelId.compareTo(b.levelId));
  }

  /// 累计签到奖励表（公开）：累计天数 → 奖励列表。
  Future<Map<int, List<SignAward>>> accumulatedAwards() async {
    final response = await _client.get('/v1/sign/accumulated_awards');
    final data = _asMap(response.data);
    final awards = <int, List<SignAward>>{};
    for (final entry in data.entries) {
      final day = int.tryParse(entry.key.trim());
      if (day == null) continue;
      final items = entry.value;
      if (items is! List) continue;
      awards[day] = items
          .whereType<Map<String, dynamic>>()
          .map(SignAward.fromJson)
          .toList(growable: false);
    }
    return awards;
  }

  Future<List<ContentPreview>> getUserArticles({
    required int userId,
    int cursor = 0,
  }) async {
    final response = await _client.get(
      '/v1/article/user_list',
      query: {'user_id': userId, 'aid': cursor, 'type': 'pass'},
    );
    return _toPreviewList(response.data);
  }

  Future<List<ContentPreview>> getUserVideos({
    required int userId,
    int cursor = 0,
  }) async {
    final response = await _client.get(
      '/v1/video/user_list',
      query: {'user_id': userId, 'vid': cursor, 'type': 'pass'},
    );
    return _toPreviewList(response.data);
  }

  /// 用户背包道具（需登录）：改名卡、补签卡等。
  Future<List<BackpackItem>> getUserBackpack() async {
    final response = await _client.get('/v1/user/get_user_backpack');
    final list = _asMap(response.data)['list'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(BackpackItem.fromJson)
        .where((item) => item.id != 0)
        .toList(growable: false);
  }

  /// 一页浏览历史及下一页游标（`/v1/history/get`，按 start_time 分页）。
  Future<HistoryPage> getHistory({double? startTime}) async {
    final response = await _client.get(
      '/v1/history/get',
      query: {if (startTime != null) 'start_time': startTime},
    );
    final list = response.data;
    double? next;
    if (list is List) {
      for (final entry in list.reversed) {
        if (entry is Map<String, dynamic>) {
          final time = _asDouble(entry['time']);
          if (time != null && time > 0) {
            next = time;
            break;
          }
        }
      }
    }
    return HistoryPage(items: _toPreviewList(list), nextStartTime: next);
  }

  Future<List<FavoriteFolder>> getFavoriteFolders(int userId) async {
    final response = await _client.get(
      '/v1/favorite/get_favorite_list',
      query: {'user_id': userId},
    );
    final data = _asMap(response.data);
    final list = data['list'];
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(FavoriteFolder.fromJson)
        .where((folder) => folder.id != 0)
        .toList(growable: false);
  }

  Future<List<ContentPreview>> getFavoriteItems(
    int favoriteId, {
    int lastId = 0,
  }) async {
    final page = await getFavoriteItemsPage(favoriteId, lastId: lastId);
    return page.items;
  }

  /// One page of a favorite folder. [nextLastId] is the cursor to pass for
  /// the next request (the server's own `last_id` when present, otherwise the
  /// last item id); null means there is no more content.
  Future<FavoriteItemsPage> getFavoriteItemsPage(
    int favoriteId, {
    int lastId = 0,
  }) async {
    final response = await _client.get(
      '/v1/favorite/get_favorite_item',
      query: {'favorite_id': favoriteId, 'last_id': lastId},
    );
    final data = _asMap(response.data);
    final items = _toPreviewList(data);
    final nextLastId = _asInt(data['last_id']) ??
        (items.isEmpty ? null : items.last.id);
    return FavoriteItemsPage(items: items, nextLastId: nextLastId);
  }

  Future<ResourceReactionStatus> getReactionStatus({
    required int resourceId,
    required int resourceType,
  }) async {
    final response = await _client.get(
      '/v1/like/status',
      query: {'id': resourceId, 'type': resourceType},
    );
    final status = _asMap(_asMap(response.data)['status']);
    final like = _asMap(status['like']);
    final dislike = _asMap(status['dislike']);
    return ResourceReactionStatus(
      liked: like['is_active'] == true || like['is_active'] == 1,
      disliked: dislike['is_active'] == true || dislike['is_active'] == 1,
      likes: _asInt(like['count']) ?? 0,
      dislikes: _asInt(dislike['count']) ?? 0,
    );
  }

  Future<void> setReaction({
    required int resourceId,
    required int resourceType,
    required String action,
  }) =>
      _client.postJson('/v1/like/$action', {
        'id': resourceId,
        'type': resourceType,
      });

  /// 投币（需登录）：`id` 为资源 id，`type` 0=文章、1=视频，
  /// `count` 为投币数量。成功返回服务端消息。
  Future<String> reward({
    required int resourceId,
    required int resourceType,
    int count = 1,
  }) async {
    final response = await _client.postJson('/v1/reward/reward', {
      'id': resourceId,
      'type': resourceType,
      'count': count,
    });
    return response.message;
  }

  Future<bool> isFavorite({
    required int resourceId,
    required int resourceType,
  }) async {
    final response = await _client.get(
      '/v1/favorite/is_favorite',
      query: {'resource_id': resourceId, 'resource_type': resourceType},
    );
    return _asMap(response.data)['is_favorite'] == true;
  }

  Future<void> addFavorite({
    required int listId,
    required int resourceId,
    required int resourceType,
  }) =>
      _client.postJson('/v1/favorite/add_favorite', {
        'list_id': listId,
        'resource_id': resourceId,
        'type': resourceType,
      });

  Future<void> removeFavorite({
    required int listId,
    required int resourceId,
    required int resourceType,
  }) =>
      _client.postJson('/v1/favorite/remove_favorite_by_resource', {
        'list_id': listId,
        'resource_id': resourceId,
        'type': resourceType,
      });

  Future<List<ContentPreview>> getRelated(ContentPreview preview) async {
    final response = await _client.get(
      '/v1/recommend/related',
      query: {
        'resource_id': preview.id,
        'resource_type': preview.type,
        'type': preview.type,
        'size': 6,
      },
    );
    return _toPreviewList(response.data)
        .where((item) => item.id != preview.id)
        .toList(growable: false);
  }

  Future<List<CommunityComment>> getComments(int areaId, {int page = 1}) async {
    final response = await _client.get(
      '/v1/comment/list',
      query: {'area_id': areaId, 'page': page, 'order': 'desc', 'html': 0},
    );
    return _toComments(response.data);
  }

  Future<List<CommunityComment>> getCommentReplies(
    int commentId, {
    int page = 1,
  }) async {
    final response = await _client.get(
      '/v1/comment/reply_list',
      query: {'comment_id': commentId, 'page': page, 'html': 0},
    );
    return _toComments(response.data);
  }

  Future<void> createComment({
    required int areaId,
    required List<CommentSpan> spans,
    List<String> images = const [],
  }) async {
    await _client.postJson('/v1/comment/create', {
      'area_id': areaId,
      'content': commentQuillJson(spans),
      'images': jsonEncode(images),
      'html': 1,
    });
  }

  Future<void> createCommentReply({
    required int commentId,
    required List<CommentSpan> spans,
  }) async {
    await _client.postJson('/v1/comment/create_reply', {
      'comment_id': commentId,
      'content': commentQuillJson(spans),
      'images': '[]',
    });
  }

  /// Likes or unlikes a comment (`type 4` = comment).
  Future<void> setCommentReaction({
    required int commentId,
    required bool like,
  }) async {
    await _client.postJson(like ? '/v1/like/like' : '/v1/like/cancel', {
      'id': commentId,
      'type': 4,
    });
  }

  /// Deletes a comment (only the author's own comments).
  Future<void> deleteComment(int commentId) async {
    await _client.postJson('/v1/comment/delete', {
      'comment_id': commentId,
    });
  }

  /// Deletes a feed post (动态).
  Future<void> deleteFeed(int feedId) async {
    await _client.postJson('/v1/feeds/delete', {'id': feedId});
  }

  /// Profile editing (`POST /v1/user/set_*`, same payloads as the web app).
  Future<void> updateUserName(String name) async {
    await _client.postJson('/v1/user/set_name', {'name': name});
  }

  Future<void> updateUserBio(String bio) async {
    await _client.postJson('/v1/user/set_bio', {'bio': bio});
  }

  Future<void> updateUserGender(int gender) async {
    await _client.postJson('/v1/user/set_gender', {'gender': gender});
  }

  /// Sets the avatar from an uploaded media path (`/static/xxx.jpg`).
  Future<void> updateUserAvatar(String path) async {
    await _client.postJson('/v1/user/set_avatar', {'avatar': path});
  }

  /// Uploads an image to the user media library and returns its relative
  /// path (`/static/xxx.jpg`) to be passed in comment `images` arrays or to
  /// `set_avatar`.
  Future<String> uploadImage(
    List<int> bytes,
    String filename,
  ) async {
    final response = await _client.postMultipart(
      '/v1/media/upload_image',
      field: 'file',
      filename: filename,
      bytes: bytes,
      fileContentType: _mimeTypeFor(filename),
    );
    final file = _asMap(_asMap(response.data)['file']);
    final path = '${file['file_path'] ?? ''}';
    if (path.isEmpty) {
      throw const MfunsApiException('图片上传响应中没有 file_path');
    }
    return path;
  }

  Future<List<MessageConversation>> getMessageConversations() async {
    final response = await _client.get('/v1/message/list');
    return _toMessageConversations(response.data);
  }

  Future<List<MessageRecord>> getMessageRecord(int userId) async {
    final response =
        await _client.get('/v1/message/record', query: {'uid': userId});
    return _toMessageRecords(response.data);
  }

  Future<void> sendMessage({
    required int toUid,
    required List<CommentSpan> spans,
    List<String> images = const [],
  }) async {
    await _client.postForm('/v1/message/send', {
      'to_uid': '$toUid',
      'msg': messageQuillJson(spans, images),
    });
  }

  Future<NotifyCounts> getNotifyCounts() async {
    final response = await _client.get('/v1/notify/count');
    return NotifyCounts.fromJson(_asMap(response.data));
  }

  /// My submissions: type 0 = article, 1 = video.
  Future<List<SubmissionItem>> getSubmissions({
    required int type,
    int page = 1,
    int size = 20,
    int? status,
  }) async {
    final response = await _client.get('/v1/contribute/list', query: {
      'type': type,
      'page': page,
      'size': size,
      if (status != null) 'status': status,
    });
    final root = _asMap(response.data);
    final rawList = response.data is List ? response.data : root['list'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(SubmissionItem.fromJson)
        .where((item) => item.id != 0)
        .toList(growable: false);
  }

  /// Total submission count for one type (0 = article, 1 = video), read
  /// from the list endpoint's `total` field with a single-item page.
  Future<int> getSubmissionTotal(int type) async {
    final response = await _client.get('/v1/contribute/list', query: {
      'type': type,
      'page': 1,
      'size': 1,
    });
    final root = _asMap(response.data);
    final total = _asInt(root['total']);
    if (total != null) return total;
    final rawList = response.data is List ? response.data : root['list'];
    return rawList is List ? rawList.length : 0;
  }

  Future<SubmissionDetail> getSubmissionDetail(int contributeId) async {
    final response = await _client
        .get('/v1/contribute/get', query: {'contribute_id': contributeId});
    return SubmissionDetail.fromJson(_asMap(response.data));
  }

  Future<void> createArticleSubmission({
    required String title,
    required String content,
    required int categoryId,
    List<String> tags = const [],
    int copyright = 2,
    String cover = '',
    bool draft = false,
  }) async {
    await _client.postJson('/v1/contribute/article/create', {
      'cid': categoryId,
      'title': title,
      'content': content,
      'content_format': 'markdown',
      'copyright': copyright,
      'draft': draft,
      if (tags.isNotEmpty) 'tags': tags.join(','),
      if (cover.isNotEmpty) 'cover': cover,
    });
  }

  Future<void> updateArticleSubmission({
    required int contributeId,
    required String title,
    required String content,
    required int categoryId,
    List<String> tags = const [],
    int copyright = 2,
    String cover = '',
    bool draft = false,
  }) async {
    await _client.postJson('/v1/contribute/article/update', {
      'contribute_id': contributeId,
      'cid': categoryId,
      'title': title,
      'content': content,
      'content_format': 'markdown',
      'copyright': copyright,
      'draft': draft,
      if (tags.isNotEmpty) 'tags': tags.join(','),
      if (cover.isNotEmpty) 'cover': cover,
    });
  }

  Future<void> updateVideoSubmission({
    required int contributeId,
    required String title,
    required String content,
    required int categoryId,
    List<String> tags = const [],
    int copyright = 0,
    String cover = '',
  }) async {
    await _client.postJson('/v1/contribute/video/update', {
      'contribute_id': contributeId,
      'cid': categoryId,
      'title': title,
      'content': jsonEncode({
        'ops': [
          {'insert': '$content\n'},
        ],
      }),
      'copyright': copyright,
      if (tags.isNotEmpty) 'tags': tags.join(','),
      if (cover.isNotEmpty) 'cover': cover,
    });
  }

  Future<void> deleteSubmission({
    required int type,
    required int contributeId,
  }) async {
    await _client.postJson(
      type == 1 ? '/v1/contribute/video/delete' : '/v1/contribute/article/delete',
      {'contribute_id': contributeId},
    );
  }

  /// Requests VOD upload credentials for a local video file.
  Future<VideoUploadAuth> getVideoUploadAuth({
    required String fileName,
    required int fileSize,
  }) async {
    final response = await _client.postJson('/v1/contribute/video/get_upload_auth', {
      'file_name': fileName,
      'file_size': fileSize,
    });
    final auth = VideoUploadAuth.fromJson(_asMap(response.data));
    if (auth.videoId.isEmpty ||
        auth.accessKeyId.isEmpty ||
        auth.bucket.isEmpty ||
        auth.objectKey.isEmpty) {
      throw const MfunsApiException('未获取到有效的上传凭证');
    }
    return auth;
  }

  /// Notifies the server the OSS upload finished; returns the video-library
  /// record id used by `video/create`.
  ///
  /// VOD verifies the object asynchronously: right after the OSS upload the
  /// server answers "视频上传未完成". Like the reference MCP client, keep
  /// retrying on that exact hint (12 attempts, 5s apart); other errors
  /// surface immediately.
  Future<int> completeVideoUpload(String videoId) async {
    const retries = 12;
    const delay = Duration(seconds: 5);
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        final response =
            await _client.postJson('/v1/contribute/video/upload_complete', {
          'videoId': videoId,
        });
        final data = _asMap(response.data);
        final libraryId = _asInt(data['id']);
        if (data['status'] == 1 || libraryId != null) {
          if (libraryId != null) return libraryId;
        }
      } on MfunsApiException catch (error) {
        if (!error.message.contains('未完成') || attempt == retries - 1) {
          rethrow;
        }
      }
      await Future<void>.delayed(delay);
    }
    throw const MfunsApiException('视频上传完成确认失败，请稍后重试');
  }

  /// Publishes a video submission from an uploaded video-library record.
  Future<void> createVideoSubmission({
    required String title,
    required String content,
    required int categoryId,
    required int videoLibraryId,
    List<String> tags = const [],
    int copyright = 0,
    String cover = '',
  }) async {
    final videos = [
      {'type': 'direct', 'content': videoLibraryId, 'title': title},
    ];
    await _client.postJson('/v1/contribute/video/create', {
      'cid': categoryId,
      'title': title,
      'content': jsonEncode({
        'ops': [
          {'insert': '$content\n'},
        ],
      }),
      'cover': cover,
      'video': jsonEncode(videos),
      'copyright': copyright,
      if (tags.isNotEmpty) 'tags': tags.join(','),
    });
  }

  /// Publishes a feed post (动态).
  Future<void> createFeed({
    required String content,
    List<String> images = const [],
    List<String> tags = const [],
  }) async {
    await _client.postJson('/v1/feeds/create', {
      'content': commentQuillJson([CommentSpan.text(content)]),
      'images': jsonEncode(images),
      if (tags.isNotEmpty) 'tags': tags.join(','),
    });
  }

  /// Resolves the comment area of a comment (notification references point
  /// at comments). Returns null when the comment is gone.
  Future<int?> getCommentAreaId(int commentId) async {
    final response =
        await _client.get('/v1/comment/get', query: {'id': commentId, 'html': 0});
    final comment = _asMap(_asMap(response.data)['comment']);
    return _asInt(comment['comment_area_id']);
  }

  /// Resolves a comment directly to its original resource, the same way the
  /// web frontend does (`/v1/comment/get_resource`). Returns
  /// `(resourceId, resourceType)` or null.
  Future<(int, int)?> getCommentResource(int commentId) async {
    final response = await _client
        .get('/v1/comment/get_resource', query: {'id': commentId});
    final data = _asMap(response.data);
    final resourceId = _asInt(data['resource_id']);
    final resourceType = _asInt(data['resource_type']);
    if (resourceId == null || resourceType == null) return null;
    return (resourceId, resourceType);
  }

  /// Resolves a comment area to its referenced resource.
  /// Returns `(resourceId, resourceType)` or null.
  Future<(int, int)?> getCommentAreaInfo(int areaId) async {
    final response = await _client
        .get('/v1/comment/area_info', query: {'area_id': areaId});
    final data = _asMap(response.data);
    final resourceId = _asInt(data['resource_id']);
    final resourceType = _asInt(data['resource_type']);
    if (resourceId == null || resourceType == null) return null;
    return (resourceId, resourceType);
  }

  Future<List<NotifyItem>> getNotifications({
    required int type,
    int page = 1,
  }) async {
    final response =
        await _client.get('/v1/notify/get', query: {'type': type, 'page': page});
    return _toNotifyItems(response.data);
  }

  Future<List<DanmakuItem>> getDanmaku(int videoId, int part) async {
    final response = await _client.get(
      '/v1/danmaku/get_normal',
      query: {'id': videoId, 'part': part},
    );
    final root = _asMap(response.data);
    final list = root['list'];
    if (list is! List) return const [];
    return list
        .map(DanmakuItem.fromJson)
        .where((item) => item.content.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> sendDanmaku({
    required int videoId,
    required int part,
    required double seconds,
    required String content,
    int type = 1,
    int color = 0xffffff,
    int size = 25,
  }) async {
    await _client.postJson('/v1/danmaku/send_normal', {
      'video_id': videoId,
      'part': part,
      'time': seconds,
      'content': content,
      'color': color,
      'size': size,
      'type': type,
    });
  }

  Future<ContentDetail> getDetail(ContentPreview preview) async {
    final response = await _client.get(
      preview.isVideo ? '/v1/video/get' : '/v1/article/get',
      query: {'id': preview.id, 'html': 1},
    );
    final root = _asMap(response.data);
    final resource = preview.isVideo ? root : _asMap(root['article']);
    final detailedPreview = _detailPreview(preview, root, resource);
    final rawContent = '${resource['content'] ?? resource['summary'] ?? ''}';
    return ContentDetail(
      preview: detailedPreview,
      content: _toPlainText(rawContent),
      rawContent: rawContent,
      tags: _toTags(root['tags'] ?? resource['tags'] ?? resource['tag']),
      commentAreaId: _asInt(
        resource['comment_area_id'] ??
            root['commentId'] ??
            root['comment_area_id'],
      ),
    );
  }

  ContentPreview _detailPreview(
    ContentPreview preview,
    Map<String, dynamic> root,
    Map<String, dynamic> resource,
  ) {
    final user = _asMap(root['user']).isEmpty
        ? _asMap(resource['user'])
        : _asMap(root['user']);
    final category = _asMap(root['category']).isEmpty
        ? _asMap(resource['category'])
        : _asMap(root['category']);
    final avatar = _coverUrl(user['avatar'] ?? user['face']);
    final like = _asMap(_asMap(root['like_status'])['like']);
    return ContentPreview(
      id: _asInt(resource['id']) ?? preview.id,
      title: '${resource['title'] ?? preview.title}',
      summary:
          '${resource['summary'] ?? resource['content'] ?? preview.summary}',
      cover: _coverUrl(resource['cover']).isEmpty
          ? preview.cover
          : _coverUrl(resource['cover']),
      author: '${user['name'] ?? user['username'] ?? preview.author}',
      category: '${category['name'] ?? preview.category}',
      type: preview.type,
      likes: _asInt(like['count']) ??
          _asInt(resource['like_count']) ??
          preview.likes,
      comments: _detailCommentCount(root, resource) ?? preview.comments,
      views:
          _asInt(root['view_count'] ?? resource['view_count']) ?? preview.views,
      authorId: _asInt(user['id'] ?? user['user_id']) ?? preview.authorId,
      authorAvatar: avatar.isEmpty ? preview.authorAvatar : avatar,
      createdAt: _asDateTime(root['created_at'] ??
              resource['created_at'] ??
              root['time'] ??
              resource['time']) ??
          preview.createdAt,
    );
  }

  /// 详情接口中的评论数：视频为 `comments.floor_count`（comments 是对象），
  /// 文章为顶层 `floor_num`；两者也兼容直接的 `comment_count` 数字字段。
  int? _detailCommentCount(
    Map<String, dynamic> root,
    Map<String, dynamic> resource,
  ) {
    var count = _asInt(root['comment_count'] ?? resource['comment_count']);
    if (count != null) return count;
    final comments = _asMap(root['comments']);
    count = _asInt(comments['floor_count'] ?? comments['floor_num']);
    if (count != null) return count;
    return _asInt(root['floor_num'] ?? resource['floor_num']);
  }

  Future<bool> followStatus(int userId) async {
    final response = await _client.get(
      '/v1/follow/status',
      query: {'user_id': userId},
    );
    final status = _asMap(response.data)['status'];
    return status == true || status == 1 || status == '1';
  }

  Future<void> setFollow({required int userId, required bool follow}) =>
      _client.postJson('/v1/follow/follow', {
        'user_id': userId,
        if (!follow) 'unfollow': 1,
      });

  /// 关注/粉丝列表（type=follow 关注 / fans 粉丝），last_id=-1 为第一页，
  /// 之后传上一页最后一个条目的 id 翻页。
  Future<List<UserProfile>> getFollowList({
    required int userId,
    required String type,
    int lastId = -1,
  }) async {
    final response = await _client.get(
      '/v1/follow/list',
      query: {
        'user_id': userId,
        'last_id': lastId,
        'type': type,
      },
    );
    final rawList = _asMap(response.data)['list'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(UserProfile.fromJson)
        .where((user) => user.id != 0)
        .toList(growable: false);
  }

  Future<List<VideoQuality>> getVideoQualities(int videoId) async {
    final response = await _client.get(
      '/v1/video/getPlayAddress',
      query: {'id': videoId},
    );
    final root = _asMap(response.data);
    final parts = root['videos'];
    if (parts is! List) return const [];

    final qualities = <VideoQuality>[];
    for (var index = 0; index < parts.length; index++) {
      final part = _asMap(parts[index]);
      final sources = part['video_url'];
      if (sources is! List) continue;
      for (final source in sources) {
        final item = _asMap(source);
        final url = '${item['url'] ?? ''}';
        if (url.isEmpty) continue;
        qualities.add(
          VideoQuality(
            part: index + 1,
            name: '${item['name'] ?? '默认清晰度'}',
            label: '${item['label'] ?? ''}',
            url: url,
          ),
        );
      }
    }
    return qualities;
  }

  List<ContentPreview> _toPreviewList(Object? data) {
    final rawList = data is List
        ? data
        : data is Map<String, dynamic>
            ? data['list']
            : null;
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(ContentPreview.fromJson)
        .where((item) => item.id != 0)
        .toList(growable: false);
  }

  List<CommunityComment> _toComments(Object? data) {
    final rawList = data is List ? data : _asMap(data)['list'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(CommunityComment.fromJson)
        .where((comment) => comment.id != 0)
        .toList(growable: false);
  }

  List<MessageConversation> _toMessageConversations(Object? data) {
    final rawList = data is List ? data : _asMap(data)['list'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(MessageConversation.fromJson)
        .where((item) => item.userId != 0)
        .toList(growable: false);
  }

  List<MessageRecord> _toMessageRecords(Object? data) {
    final rawList = data is List ? data : _asMap(data)['list'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(MessageRecord.fromJson)
        .toList(growable: false);
  }

  List<NotifyItem> _toNotifyItems(Object? data) {
    final rawList = data is List ? data : _asMap(data)['list'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(NotifyItem.fromJson)
        .toList(growable: false);
  }

  List<TimelineFeed> _toTimelineFeeds(Object? data) {
    final root = _asMap(data);
    final rawList =
        data is List ? data : root['list'] ?? root['feeds'] ?? root['data'];
    if (rawList is! List) return const [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(TimelineFeed.fromJson)
        .where((item) => item.id != 0)
        .toList(growable: false);
  }

  void _collectCategories(Object? raw, List<CategoryNode> output) {
    if (raw is List) {
      for (final item in raw) {
        _collectCategories(item, output);
      }
      return;
    }
    final item = _asMap(raw);
    if (item.isEmpty) return;
    if (item.containsKey('id') && item.containsKey('name')) {
      output.add(CategoryNode.fromJson(item));
    }
    _collectCategories(item['children'], output);
    _collectCategories(item['list'], output);
  }
}

List<String> _toTags(Object? value) {
  if (value is String) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is String) return item;
        if (item is Map<String, dynamic>) {
          return '${item['name'] ?? item['title'] ?? ''}';
        }
        return '';
      })
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

String _toPlainText(String raw) {
  if (raw.isEmpty) return '暂无简介';
  final trimmed = raw.trim();
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      final ops = _asMap(decoded)['ops'];
      if (ops is List) {
        final text = ops
            .whereType<Map<String, dynamic>>()
            .map((item) => item['insert'])
            .whereType<String>()
            .join()
            .trim();
        if (text.isNotEmpty) return text;
      }
    } on FormatException {
      // Fall back to the ordinary HTML/text normalization below.
    }
  }
  return _htmlToText(raw);
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

/// 等级徽章 ID 固定为 1-10（D/D+/C/C+/B/B+/A/A+/S/S+），用户 `badges`
/// 列表中第一个落在该区间的 ID 即其等级。兼容旧版 `level_id` 字段。
int? _levelFromBadges(Object? value) {
  if (value is! List) return null;
  for (final entry in value) {
    final id = entry is Map
        ? _asInt(entry['badge_id'] ?? entry['id'])
        : _asInt(entry);
    if (id != null && id >= 1 && id <= 10) return id;
  }
  return null;
}

/// 解析签到日期列表为当月"日"数组。
///
/// 服务端 `list` 是 1 索引的当月每日状态数组：`list[0]` 为占位项，
/// `list[i] == "1"` 表示第 i 天已签到（与 Web 端 `sign[day]` 一致）；
/// 同时兼容旧格式的数字列表（[1, 3, 5]）与 "2026-08-03" 这类日期字符串。
List<int> _signDays(Object? value) {
  if (value is! List) return const [];
  final entries = value.toList(growable: false);
  if (entries.isNotEmpty &&
      entries.every((entry) {
        final text = '$entry'.trim();
        return text == '0' || text == '1';
      })) {
    final days = <int>[];
    for (var i = 0; i < entries.length; i++) {
      if (i > 0 && '${entries[i]}'.trim() == '1') days.add(i);
    }
    return days;
  }
  final days = <int>[];
  for (final entry in entries) {
    final intValue = _asInt(entry);
    if (intValue != null && intValue >= 1 && intValue <= 31) {
      days.add(intValue);
      continue;
    }
    final parts = '$entry'.split('-');
    final day = int.tryParse(parts.last.trim());
    if (day != null && day >= 1 && day <= 31) days.add(day);
  }
  return days;
}

int? _resourceTypeFromText(String value) {
  final type = value.trim().toLowerCase();
  if (type.contains('video')) return 1;
  if (type.contains('article') || type.contains('post')) return 0;
  if (type.contains('feed') ||
      type.contains('dynamic') ||
      type.contains('comment')) {
    return 4;
  }
  return null;
}

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

int _asResourceType(Object? value) {
  final numeric = _asInt(value);
  if (numeric != null) return numeric;
  final type = '$value'.toLowerCase();
  return type.contains('video') ? 1 : 0;
}

double? _asDouble(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

DateTime? _asDateTime(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
    if (parsed != null) return parsed.toLocal();
  }
  final seconds = _asInt(value);
  if (seconds == null || seconds <= 0) return null;
  final milliseconds = seconds > 100000000000 ? seconds : seconds * 1000;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
}

String _coverUrl(Object? value) {
  final cover = '${value ?? ''}'.trim();
  if (cover.isEmpty) return '';
  if (cover.startsWith('//')) return 'https:$cover';
  // API payloads use `/static/...` for covers and avatars. Those paths are
  // image bytes on the CDN; the same path on api.mfuns.net is a JSON response.
  if (cover.startsWith('/')) return 'https://cdn2.mfuns.net$cover';
  if (cover.startsWith('static/')) return 'https://cdn2.mfuns.net/$cover';
  return cover;
}

List<String> _feedImages(Object? value) {
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty) return const [];
    if (!text.startsWith('[')) return [_coverUrl(text)];
    try {
      return _feedImages(jsonDecode(text));
    } on FormatException {
      return const [];
    }
  }
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is String) return _coverUrl(item);
        final source = _asMap(item);
        return _coverUrl(source['url'] ?? source['src'] ?? source['image']);
      })
      .where((url) => url.isNotEmpty)
      .toList(growable: false);
}

/// 从消息/评论内容本身提取图片地址，兜底服务端未单独返回 `images` 字段、
/// 而是把图片嵌在 Quill 内容（`{"insert":{"image":"..."}}`）或 HTML
/// `<img src="...">` 中的情况。返回绝对 CDN URL。
List<String> _contentImages(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return const [];
  if (value.startsWith('{')) {
    try {
      final ops = _asMap(jsonDecode(value))['ops'];
      if (ops is List) {
        return ops
            .whereType<Map<String, dynamic>>()
            .map((op) {
              final insert = op['insert'];
              if (insert is Map<String, dynamic>) {
                final image = insert['image'];
                if (image is String && image.isNotEmpty) return image;
              }
              return null;
            })
            .whereType<String>()
            .map(_coverUrl)
            .where((url) => url.isNotEmpty)
            .toList(growable: false);
      }
    } on FormatException {
      // Fall through to the HTML handling below.
    }
  }
  final imgPattern = RegExp(
      r'''<img[^>]*\bsrc=['"]([^'"]+)['"]''', caseSensitive: false);
  return imgPattern
      .allMatches(value)
      .map((match) => _coverUrl(match.group(1) ?? ''))
      .where((url) => url.isNotEmpty)
      .toList(growable: false);
}

List<String> _uniqueImages(List<String> urls) {
  final seen = <String>{};
  final result = <String>[];
  for (final url in urls) {
    if (url.isNotEmpty && seen.add(url)) result.add(url);
  }
  return result;
}

String _mimeTypeFor(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  if (lower.endsWith('.svg')) return 'image/svg+xml';
  return 'image/jpeg';
}

String _quillToText(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  if (!value.startsWith('{')) return value;
  try {
    final ops = _asMap(jsonDecode(value))['ops'];
    if (ops is List) {
      final parts = ops.whereType<Map<String, dynamic>>().map((item) {
        final insert = item['insert'];
        if (insert is String) return insert;
        if (insert is Map<String, dynamic>) {
          if (insert['sticker'] is String) return '[表情]';
          final mention = insert['mention'];
          if (mention is Map<String, dynamic>) {
            return '@${mention['value'] ?? ''}';
          }
        }
        return '';
      });
      return parts.join().trim();
    }
  } on FormatException {
    // Fall back to the raw text below.
  }
  return value;
}
