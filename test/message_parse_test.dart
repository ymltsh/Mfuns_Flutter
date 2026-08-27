import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('parses a message conversation with user and last message', () {
    final conv = MessageConversation.fromJson({
      'user': {'id': 7, 'name': '小明', 'avatar': '/static/avatar.png'},
      'no_read': 3,
      'last_msg': {
        'data': {
          'message': '{"ops":[{"insert":"最近一条消息\\n"}]}',
          'time': 1720000000,
        }
      },
    });
    expect(conv.userId, 7);
    expect(conv.userName, '小明');
    expect(conv.userAvatar, 'https://cdn2.mfuns.net/static/avatar.png');
    expect(conv.unread, 3);
    expect(conv.lastMessage, '最近一条消息');
    expect(conv.lastTime, isNotNull);
  });

  test('parses message records and identifies senders', () {
    final mine = MessageRecord.fromJson({
      'uid': 5,
      'data': {'message': '{"ops":[{"insert":"你好"}]}', 'time': 1720000001},
    });
    final peer = MessageRecord.fromJson({
      'uid': 7,
      'data': {'message': '纯文本消息', 'time': 1720000002},
    });
    expect(mine.uid, 5);
    expect(mine.message, '你好');
    expect(peer.message, '纯文本消息');
  });

  test('parses stickers out of message records', () {
    final record = MessageRecord.fromJson({
      'uid': 7,
      'data': {
        'message':
            '{"ops":[{"insert":{"sticker":"s-1"}},{"insert":"冲鸭\\n"}]}',
        'time': 1720000003,
      },
    });
    expect(record.spans.length, 2);
    expect(record.spans[0].isSticker, isTrue);
    expect(record.spans[0].stickerKey, 's-1');
    expect(record.spans[1].text, '冲鸭');
    expect(record.message, '[表情]冲鸭');
  });

  test('parses images out of message records', () {
    final record = MessageRecord.fromJson({
      'uid': 7,
      'data': {
        'message': '{"ops":[{"insert":"\\n"}]}',
        'images': '["/static/a.png","/static/b.jpg"]',
        'time': 1720000003,
      },
    });
    expect(record.images,
        ['https://cdn2.mfuns.net/static/a.png', 'https://cdn2.mfuns.net/static/b.jpg']);
    expect(record.message, isEmpty);

    final plain = MessageRecord.fromJson({
      'uid': 7,
      'data': {'message': '纯文本消息'},
    });
    expect(plain.images, isEmpty);
  });

  test('extracts images embedded in quill content', () {
    final record = MessageRecord.fromJson({
      'uid': 7,
      'data': {
        'message': '{"ops":[{"insert":{"image":"/static/embed.png"}}]}',
        'time': 1720000004,
      },
    });
    expect(record.images, ['https://cdn2.mfuns.net/static/embed.png']);
    expect(record.message, isEmpty);
    expect(record.spans, isEmpty);
  });

  test('extracts images from html img tags and dedupes', () {
    final record = MessageRecord.fromJson({
      'uid': 7,
      'data': {
        'message': '<p><img src="/static/x.png"></p>',
        'images': '["/static/x.png"]',
      },
    });
    expect(record.images, ['https://cdn2.mfuns.net/static/x.png']);
  });

  test('embeds images into quill content when sending', () {
    final json = messageQuillJson(
        const [CommentSpan.text('看图')], const ['/static/a.png']);
    final ops = (jsonDecode(json) as Map<String, dynamic>)['ops'] as List;
    expect(ops[0], {'insert': '看图\n'});
    expect(ops[1], {'insert': {'image': '/static/a.png'}});
    expect(ops, hasLength(3));

    final onlyImage = messageQuillJson(const [], ['/static/a.png']);
    final onlyOps =
        (jsonDecode(onlyImage) as Map<String, dynamic>)['ops'] as List;
    expect(onlyOps, hasLength(2));
    expect(onlyOps[0], {'insert': {'image': '/static/a.png'}});
    expect(onlyOps[1], {'insert': '\n'});
  });

  test('previews image-only last message in conversation', () {
    final conv = MessageConversation.fromJson({
      'user': {'id': 7, 'name': '小明'},
      'last_msg': {
        'data': {
          'message': '{"ops":[{"insert":"\\n"}]}',
          'images': '["/static/a.png"]',
        }
      },
    });
    expect(conv.lastMessage, '[图片]');
  });

  test('reads referenced content info from notify params', () {
    final item = NotifyItem.fromJson({
      'sender_user_id': 9,
      'notify_params': {
        'text': '赞了你的评论',
        'comment_id': 42,
        'resource_id': 123,
        'resource_type': 0,
      },
    });
    expect(item.commentId, 42);
    expect(item.resourceId, 123);
    expect(item.resourceType, 0);
  });

  test('parses string resource types and nested resource objects', () {
    final video = NotifyItem.fromJson({
      'notify_params': {
        'text': '提及了你',
        'comment_id': 7,
        'resource': {'id': 999, 'type': 'video'},
      },
    });
    expect(video.resourceId, 999);
    expect(video.resourceType, 1);

    final feed = NotifyItem.fromJson({
      'notify_params': {
        'text': '回复了你',
        'comment_id': 8,
        'resource_type': 'dynamic',
      },
    });
    expect(feed.resourceType, 4);
  });

  test('parses top-level content_id / content_type used by like and mention',
      () {
    final like = NotifyItem.fromJson({
      'sender_user_id': 72268,
      'content_id': 60564,
      'content_type': 1,
      'notify_type': 1,
      'notify_params': {'text': '赞了你的视频', 'count': 4},
    });
    expect(like.resourceId, 60564);
    expect(like.resourceType, 1);
    expect(like.commentId, isNull);

    final mentionOnComment = NotifyItem.fromJson({
      'sender_user_id': 38461,
      'content_id': 1211422,
      'content_type': 4,
      'notify_type': 3,
      'notify_params': {'text': '@了你', 'type': '在评论里@'},
    });
    expect(mentionOnComment.resourceId, 1211422);
    expect(mentionOnComment.resourceType, 4);

    final mentionOnArticle = NotifyItem.fromJson({
      'content_id': 218602,
      'content_type': 3,
      'notify_type': 3,
      'notify_params': {'text': '在动态里@了博主'},
    });
    expect(mentionOnArticle.resourceId, 218602);
    expect(mentionOnArticle.resourceType, 3);
  });

  test('parses notify counts and items', () {
    final counts = NotifyCounts.fromJson(
        {'like': 2, 'comment': 5, 'mention': 1, 'system': 0});
    expect(counts.like, 2);
    expect(counts.comment, 5);

    final item = NotifyItem.fromJson({
      'sender_user_id': 9,
      'created_at': 1720000000,
      'notify_params': {
        'text': '{"ops":[{"insert":"赞了你的评论\\n"}]}',
        'comment_id': 42,
      },
    });
    expect(item.senderUserId, 9);
    expect(item.text, '赞了你的评论');
    expect(item.commentId, 42);
  });

  test('reads sender info from a nested user object', () {
    final item = NotifyItem.fromJson({
      'user': {'id': 12, 'name': '小红', 'avatar': '/static/notify.png'},
      'notify_params': {'reply_text': '回复了你'},
    });
    expect(item.senderUserId, 12);
    expect(item.senderName, '小红');
    expect(item.senderAvatar, 'https://cdn2.mfuns.net/static/notify.png');
    expect(item.text, '回复了你');
  });
}
