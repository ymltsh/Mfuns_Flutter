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

  test('parses a mention out of quill content', () {
    final comment = CommunityComment.fromJson({
      'id': 106,
      'content':
          '{"ops":[{"insert":{"mention":{"id":"38461","value":"少女乌斯"}}},{"insert":"QWQ\\n"}]}',
    });
    expect(comment.spans, hasLength(2));
    expect(comment.spans[0].isMention, isTrue);
    expect(comment.spans[0].mentionId, '38461');
    expect(comment.spans[0].mentionName, '少女乌斯');
    expect(comment.spans[1].text, 'QWQ');
    expect(comment.content, '@少女乌斯QWQ');
  });

  test('converts mention markers in text to mention spans', () {
    final spans = commentSpansFromText('[@少女乌斯]来啦 [s-1]');
    expect(spans, hasLength(3));
    expect(spans[0].isMention, isTrue);
    expect(spans[0].mentionName, '少女乌斯');
    expect(spans[0].mentionId, '');
    expect(spans[1].text, '来啦 ');
    expect(spans[2].isSticker, isTrue);
  });

  test('carries mention id through the id-prefixed marker', () {
    final spans = commentSpansFromText('[@38461:少女乌斯]QWQ');
    expect(spans, hasLength(2));
    expect(spans[0].isMention, isTrue);
    expect(spans[0].mentionId, '38461');
    expect(spans[0].mentionName, '少女乌斯');
    expect(spans[1].text, 'QWQ');

    final nameWithColon = commentSpansFromText('[@少女:乌斯]');
    expect(nameWithColon.single.isMention, isTrue);
    expect(nameWithColon.single.mentionId, '');
    expect(nameWithColon.single.mentionName, '少女:乌斯');
  });

  test('serializes mentions into quill ops', () {
    final payload = commentQuillJson([
      CommentSpan.mention('38461', '少女乌斯'),
      CommentSpan.text('QWQ'),
    ]);
    expect(payload,
        '{"ops":[{"insert":{"mention":{"id":"38461","value":"少女乌斯"}}},{"insert":"QWQ\\n"}]}');
  });
}
