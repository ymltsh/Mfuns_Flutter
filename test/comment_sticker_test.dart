import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/emoji/emoji_pack_store.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('parses comment spans with stickers in order', () {
    final comment = CommunityComment.fromJson({
      'id': 201,
      'user_id': 7,
      'content':
          '{"ops":[{"insert":{"sticker":"s-1"}},{"insert":"(￣-￣)つロ"},{"insert":{"sticker":"family-1"}},{"insert":"\\n"}]}',
    });
    expect(comment.spans.length, 3);
    expect(comment.spans[0].isSticker, isTrue);
    expect(comment.spans[0].stickerKey, 's-1');
    expect(comment.spans[1].isSticker, isFalse);
    expect(comment.spans[1].text, '(￣-￣)つロ');
    expect(comment.spans[2].stickerKey, 'family-1');
    expect(comment.content, '(￣-￣)つロ');
  });

  test('sticker-only comment keeps an empty text content', () {
    final comment = CommunityComment.fromJson({
      'id': 202,
      'user_id': 7,
      'content': '{"ops":[{"insert":{"sticker":"stick-3"}},{"insert":"\\n"}]}',
    });
    expect(comment.spans.length, 1);
    expect(comment.spans.single.stickerKey, 'stick-3');
    expect(comment.content, '');
  });

  test('round-trips spans into the quill JSON used for posting', () {
    final spans = <CommentSpan>[
      const CommentSpan.sticker('s-1'),
      const CommentSpan.text('文本'),
      const CommentSpan.sticker('family-2'),
    ];
    final json = commentQuillJson(spans);
    final parsed = CommunityComment.fromJson({'id': 203, 'content': json});
    final normalized = parsed.spans
        .map((span) => span.isSticker
            ? span
            : CommentSpan.text(span.text.replaceAll(RegExp(r'\n+$'), '')))
        .toList();
    expect(normalized, spans);
    expect(json, contains('{"insert":{"sticker":"s-1"}}'));
    expect(json, contains('{"insert":"文本\\n"}'));
  });

  test('parses the HTML comment bodies returned with html=1', () {
    final comment = CommunityComment.fromJson({
      'id': 204,
      'user_id': 7,
      'content':
          "<p>HELLO</p><p>_............<img class='sticker' width='50px' src='https://resource.mfuns.net/image/sticker/s/1.png' alt='[s-1]'/></p>",
    });
    expect(comment.spans.length, 2);
    expect(comment.spans[0].isSticker, isFalse);
    expect(comment.spans[0].text, 'HELLO _............');
    expect(comment.spans[1].isSticker, isTrue);
    expect(comment.spans[1].stickerKey, 's-1');
    expect(comment.content, 'HELLO _............');
  });

  test('derives the sticker key from src when alt is missing', () {
    final spans = CommunityComment.fromJson({
      'id': 205,
      'user_id': 7,
      'content':
          "<p><img class='sticker' src='https://resource.mfuns.net/image/sticker/family/3.gif'/></p>",
    }).spans;
    expect(spans.single.isSticker, isTrue);
    expect(spans.single.stickerKey, 'family-3');
  });

  test('parses comment images from content_ext and resolves CDN urls', () {
    final comment = CommunityComment.fromJson({
      'id': 206,
      'user_id': 7,
      'content': '{"ops":[{"insert":"看这张图\\n"}]}',
      'content_ext': {
        'images': ['/static/af1adc8e.jpg'],
      },
    });
    expect(comment.images,
        ['https://cdn2.mfuns.net/static/af1adc8e.jpg']);
    expect(comment.content, '看这张图');
  });

  test('emits images array in the create payload style', () {
    final comment = CommunityComment.fromJson({
      'id': 207,
      'user_id': 7,
      'content': '<p>hello</p>',
      'content_ext': {'images': []},
    });
    expect(comment.images, isEmpty);
  });

  test('converts [pack-id] text markers into sticker spans', () {
    final spans =
        commentSpansFromText('[s-1]你好呀[family-2]，[stick-3]');
    expect(spans.length, 5);
    expect(spans[0].isSticker, isTrue);
    expect(spans[0].stickerKey, 's-1');
    expect(spans[1].text, '你好呀');
    expect(spans[2].stickerKey, 'family-2');
    expect(spans[3].text, '，');
    expect(spans[4].stickerKey, 'stick-3');
  });

  test('keeps plain text without markers as a single span', () {
    final spans = commentSpansFromText('今天天气不错');
    expect(spans.length, 1);
    expect(spans.single.text, '今天天气不错');
  });

  test('ignores brackets that do not look like sticker markers', () {
    final spans = commentSpansFromText('试试[括号]文字[s]和[-1]');
    expect(spans.length, 1);
    expect(spans.single.text, '试试[括号]文字[s]和[-1]');
  });

  test('round-trips marker text through spans and quill json', () {
    const text = '冲鸭[s-1]';
    final spans = commentSpansFromText(text);
    final json = commentQuillJson(spans);
    expect(json, contains('{"insert":{"sticker":"s-1"}}'));
    expect(json, contains('{"insert":"冲鸭\\n"}'));
  });

  test('decodes html entities in comment text', () {
    final comment = CommunityComment.fromJson({
      'id': 208,
      'user_id': 7,
      'content':
          "<p>Tom&#039;s &quot;great&quot; idea: a &lt;b&gt; &amp; c &#x1F600;</p>",
    });
    expect(comment.content, "Tom's \"great\" idea: a <b> & c 😀");
  });

  test('keeps literal ampersands that are not entities', () {
    final comment = CommunityComment.fromJson({
      'id': 209,
      'user_id': 7,
      'content': '<p>R&amp;D 团队 & 开发</p>',
    });
    expect(comment.content, 'R&D 团队 & 开发');
  });

  test('decodes entities mixed with stickers', () {
    final spans = CommunityComment.fromJson({
      'id': 210,
      'user_id': 7,
      'content':
          "<p>It&#039;s fine<img class='sticker' src='https://resource.mfuns.net/image/sticker/s/1.png' alt='[s-1]'/>okay</p>",
    }).spans;
    expect(spans[0].text, "It's fine");
    expect(spans[1].stickerKey, 's-1');
    expect(spans[2].text, 'okay');
  });

  test('parses emoji pack data and resolves sticker urls', () {
    final data = EmojiData.fromJson({
      's': {
        'name': '冲鸭头像',
        'list': {
          '1': {'url': 'https://resource.mfuns.net/image/sticker/s/1.png', 'size': 50},
          '2': {'url': 'https://resource.mfuns.net/image/sticker/s/2.png', 'size': 50},
        },
      },
      'family': {
        'name': 'Family',
        'list': {
          '1': {'url': 'https://resource.mfuns.net/image/sticker/family/1.png', 'size': 60},
        },
      },
    }, ['(￣-￣)つロ', '(°▽°)']);
    expect(data.packs.length, 2);
    expect(data.packs.first.key, 's');
    expect(data.packs.first.name, '冲鸭头像');
    expect(data.stickerUrl('s-2'),
        'https://resource.mfuns.net/image/sticker/s/2.png');
    expect(data.stickerUrl('family-1'),
        'https://resource.mfuns.net/image/sticker/family/1.png');
    expect(data.stickerUrl('unknown-1'), isNull);
    expect(data.stickerUrl('no-separator'), isNull);
    expect(data.faceTexts, ['(￣-￣)つロ', '(°▽°)']);
  });
}
