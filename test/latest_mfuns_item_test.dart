import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/latest/latest_mfuns_repository.dart';

void main() {
  test('parses the new Flutter latest-mfuns contract', () {
    final item = LatestMfunsItem.fromJson({
      'id': 12,
      'type': 'video',
      'title': '最新视频',
      'content': '视频简介',
      'cover': '/static/cover.webp',
      'created_at': 1700000000,
      'user': {
        'id': 9,
        'name': '发布者',
        'avatar': '/static/avatar.webp',
      },
      'like_count': 5,
      'comment_count': 3,
      'view_count': 80,
      'category_name': '动画',
      'source_url': 'https://m.mfuns.net/video/12',
    });

    expect(item.isVideo, isTrue);
    expect(item.authorId, 9);
    expect(item.cover, 'https://cdn2.mfuns.net/static/cover.webp');
    expect(item.authorAvatar, 'https://cdn2.mfuns.net/static/avatar.webp');
    expect(item.contentPreview.type, 1);
  });

  test('parses the legacy latest endpoint during server rollout', () {
    final item = LatestMfunsItem.fromJson({
      'id': 13,
      'type': 'article',
      'title': '兼容文章',
      'description': '旧接口简介',
      'created_at': '2026-08-11 12:00:00',
      'author': '旧接口作者',
      'author_id': '10',
      'author_avatar': 'https://cdn2.mfuns.net/static/avatar.jpg',
      'likes': 2,
      'comments': 1,
      'views': 20,
      'category': '科技',
      'url': 'https://m.mfuns.net/article/13',
    });

    expect(item.isArticle, isTrue);
    expect(item.author, '旧接口作者');
    expect(item.authorId, 10);
    expect(item.content, '旧接口简介');
    expect(item.contentPreview.category, '科技');
  });

  test('parses mark fields and copyWith keeps them', () {
    final item = LatestMfunsItem.fromJson({
      'id': 14,
      'type': 'feed',
      'created_at': 1700000000,
      'mark_count': 3,
      'marked_by_me': true,
    });

    expect(item.markCount, 3);
    expect(item.markedByMe, isTrue);

    final marked = item.copyWith(markCount: 4);
    expect(marked.markCount, 4);
    expect(marked.markedByMe, isTrue);
    expect(marked.stableId, item.stableId);
  });

  test('defaults mark fields to zero/unmarked', () {
    final item = LatestMfunsItem.fromJson({
      'id': 15,
      'type': 'video',
      'created_at': 1700000000,
    });
    expect(item.markCount, 0);
    expect(item.markedByMe, isFalse);
  });
}
