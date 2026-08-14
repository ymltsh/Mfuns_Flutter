import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('parses a comment with an embedded user object', () {
    final comment = CommunityComment.fromJson({
      'id': 101,
      'comment_area_id': 9,
      'user_id': 7,
      'content': '<p>评论内容</p>',
      'like_count': 3,
      'reply_count': 1,
      'created_at': '2026-08-11 10:00:00',
      'user': {
        'id': 7,
        'name': '小明',
        'avatar': '/static/comment_avatar.png',
      },
    });
    expect(comment.id, 101);
    expect(comment.userId, 7);
    expect(comment.authorName, '小明');
    expect(comment.avatar, 'https://cdn2.mfuns.net/static/comment_avatar.png');
    expect(comment.content, '评论内容');
    expect(comment.likes, 3);
    expect(comment.replyCount, 1);
  });

  test('falls back to user_id when no user object is present', () {
    final comment = CommunityComment.fromJson({
      'id': 102,
      'user_id': 88,
      'content': '没有用户信息的评论',
    });
    expect(comment.userId, 88);
    expect(comment.authorName, '');
    expect(comment.avatar, '');
    expect(comment.likes, 0);
  });

  test('reads user info from a user_info object', () {
    final comment = CommunityComment.fromJson({
      'id': 103,
      'content': 'x',
      'user_info': {'user_id': 12, 'username': '小红'},
    });
    expect(comment.userId, 12);
    expect(comment.authorName, '小红');
  });

  test('parses like count and active state from like_status', () {
    final liked = CommunityComment.fromJson({
      'id': 104,
      'content': 'x',
      'like_status': {
        'like': {'count': 5, 'is_active': true},
      },
    });
    expect(liked.likes, 5);
    expect(liked.liked, isTrue);

    final notLiked = CommunityComment.fromJson({
      'id': 105,
      'content': 'x',
      'like_count': 3,
    });
    expect(notLiked.likes, 3);
    expect(notLiked.liked, isFalse);
  });
}
