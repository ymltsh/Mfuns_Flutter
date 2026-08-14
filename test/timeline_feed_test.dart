import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('parses a timeline feed and its media without treating it as content',
      () {
    final feed = TimelineFeed.fromJson({
      'feed_id': 42,
      'content': '<p>今天的动态</p>',
      'created_at': '2026-08-11 09:30:00',
      'like_count': 5,
      'comment_count': 2,
      'view_count': 18,
      'images': '["//cdn.example.test/feed.png"]',
      'user': {
        'id': 7,
        'name': '喵友',
        'avatar': '//cdn.example.test/avatar.png',
      },
    });

    expect(feed.id, 42);
    expect(feed.author, '喵友');
    expect(feed.authorId, 7);
    expect(feed.content, '今天的动态');
    expect(feed.images, ['https://cdn.example.test/feed.png']);
    expect(feed.avatar, 'https://cdn.example.test/avatar.png');
    expect(feed.createdAt, DateTime(2026, 8, 11, 9, 30));
    expect(feed.resource, isNull);
  });

  test('parses the official auto-sync timeline schema from the browser', () {
    final feed = TimelineFeed.fromJson({
      'id': 272373,
      'user_id': 17627,
      'resource_id': 60586,
      'resource_type': 1,
      'content': '<p>一条同步动态</p>',
      'created_at': 1786341418,
      'views': 20,
      'like_status': {
        'like': {'count': 2, 'is_active': false},
      },
      'user': {
        'id': 17627,
        'name': '微风与少年',
        'avatar': '/static/avatar.jpg',
      },
      'extra': {
        'resource': {
          'id': 60586,
          'type': 1,
          'title': '云的彼端，约定的地方',
          'cover': '/static/cover.jpg',
          'like_count': 2,
          'comment_count': 0,
          'view_count': 20,
        },
      },
    });

    expect(feed.authorId, 17627);
    expect(feed.content, '一条同步动态');
    expect(feed.likes, 2);
    expect(feed.resource?.id, 60586);
    expect(feed.resource?.isVideo, isTrue);
  });

  test('parses images from the new_reply_list extra payload', () {
    final feed = TimelineFeed.fromJson({
      'id': 17,
      'content': '<p>带图的时间线动态</p>',
      'extra': {
        'images': [
          {'url': '/static/feed-image.jpg'},
        ],
      },
      'user': {'id': 8, 'name': '测试用户'},
    });

    expect(feed.images, ['https://cdn2.mfuns.net/static/feed-image.jpg']);
  });

  test('parses the home recommendation schema from the mobile site', () {
    final item = ContentPreview.fromJson({
      'id': 99,
      'title': '首页推荐内容',
      'summary': '来自真实推荐接口的字段组合',
      'cover': '/static/recommend-cover.jpg',
      'type': 1,
      'like_count': 8,
      'comment_count': 3,
      'view_count': 120,
      'user': {'name': '推荐作者'},
      'category': {'name': '动画'},
    });

    expect(item.id, 99);
    expect(item.isVideo, isTrue);
    expect(item.cover, 'https://cdn2.mfuns.net/static/recommend-cover.jpg');
    expect(item.author, '推荐作者');
    expect(item.authorId, isNull);
    expect(item.category, '动画');
  });

  test('keeps a resource author identity for detail-page navigation', () {
    final item = ContentPreview.fromJson({
      'id': 100,
      'title': '视频',
      'type': 1,
      'user': {
        'id': 17627,
        'name': '视频作者',
        'avatar': '/static/author-avatar.webp',
      },
    });

    expect(item.authorId, 17627);
    expect(
        item.authorAvatar, 'https://cdn2.mfuns.net/static/author-avatar.webp');
  });
}
