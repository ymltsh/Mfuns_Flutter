import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/content/rich_content_card.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('normalizes the article HTML returned by the mobile page', () {
    final markdown = normalizeRichContent('''
      <h2>亮点</h2><p><strong>批量投稿</strong>，一条命令完成。</p>
      <ul><li>分 P</li><li>断点续传</li></ul>
      <pre>python -m upload</pre><p><a href="https://example.test/doc">文档</a></p>
    ''');

    expect(markdown, contains('## 亮点'));
    expect(markdown, contains('**批量投稿**'));
    expect(markdown, contains('- 分 P'));
    expect(markdown, contains('```\npython -m upload\n```'));
    expect(markdown, contains('[文档](https://example.test/doc)'));
  });

  test('drops unsafe HTML links while keeping visible text', () {
    expect(
      normalizeRichContent('<p><a href="javascript:alert(1)">危险链接</a></p>'),
      '危险链接',
    );
  });

  test('renders private-pack stickers inline instead of full-width images',
      () {
    final markdown = normalizeRichContent(
        '<p>太棒了<img class="sticker" width="50px" '
        'src="https://resource.mfuns.net/image/sticker/s/1.png" '
        "alt='[s-1]'/></p>");
    expect(markdown, contains('![sticker:s-1]('));
    expect(markdown, isNot(contains('![图片](')));
    expect(markdown.trim().contains('\n\n'), isFalse);
  });

  test('derives sticker key from src when alt is missing', () {
    final markdown = normalizeRichContent(
        '<p>冲鸭<img class=\'sticker\' '
        'src="https://resource.mfuns.net/image/sticker/family/3.gif"/></p>');
    expect(markdown, contains('![sticker:family-3]('));
  });

  test('keeps regular images as block images', () {
    final markdown = normalizeRichContent(
        '<p><img src="https://example.test/photo.jpg" alt="照片"/></p>');
    expect(markdown, contains('![照片](https://example.test/photo.jpg)'));
    expect(markdown, isNot(contains('sticker:')));
  });

  test('converts quill json content with stickers to markdown', () {
    final markdown = normalizeRichContent(
        '{"ops":[{"insert":{"sticker":"simple-5"}},{"insert":"赞\\n"}]}');
    expect(markdown, contains('![sticker:simple-5]('));
    expect(markdown, contains('赞'));
  });

  test('extracts sticker spans from feed content html', () {
    final feed = TimelineFeed.fromJson({
      'feed_id': 270931,
      'content':
          "<p>为什么<img class='sticker' width='50px' src='https://resource.mfuns.net//image/sticker/simple/1.jpg' alt='[simple-5]'/></p>",
      'user': {'id': 64941, 'name': '某用户', 'avatar': '/static/a.png'},
    });
    expect(feed.spans.any((span) => span.isSticker), isTrue);
    expect(
      feed.spans.firstWhere((span) => span.isSticker).stickerKey,
      'simple-5',
    );
  });
}
