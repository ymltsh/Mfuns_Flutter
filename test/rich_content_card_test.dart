import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/content/rich_content_card.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test(
    'opens the original CDN image while preserving other query parameters',
    () {
      final thumbnail = Uri.parse(
        'https://cdn2.mfuns.net/static/photo.jpg?image_process=resize,w_800&v=2',
      );
      expect(
        originalArticleImageUri(thumbnail).toString(),
        'https://cdn2.mfuns.net/static/photo.jpg?v=2',
      );
      expect(
        originalArticleImageUri(
          Uri.parse(
            'https://cdn2.mfuns.net/static/photo.jpg?image_process=resize,w_800',
          ),
        ).toString(),
        'https://cdn2.mfuns.net/static/photo.jpg',
      );
      expect(
        originalArticleImageUri(
          Uri.parse(
            'https://example.test/photo.jpg?image_process=resize,w_800',
          ),
        ).toString(),
        'https://example.test/photo.jpg?image_process=resize,w_800',
      );
    },
  );

  test('reads image ratio from HTML and ignores missing dimensions', () {
    const thumbnail =
        'https://cdn2.mfuns.net/static/photo.jpg?image_process=resize,w_800';
    const mfunsThumbnail =
        'https://cdn2.mfuns.net/static/article.png?image_process=resize,w_800';
    final ratios = articleImageAspectRatios(
      '<p><img src="$thumbnail" width="800" height="400"></p>'
      '<p><img src="$mfunsThumbnail" '
      'src-origin="https://cdn2.mfuns.net/static/article.png?image_process=resize,w_1500" '
      'data-width="1448" data-height="2048" class="preview"></p>'
      '<p><img src="https://example.test/unknown.jpg"></p>',
    );
    expect(ratios[Uri.parse(thumbnail)], 2);
    expect(ratios[Uri.parse(mfunsThumbnail)], 1448 / 2048);
    expect(ratios, hasLength(2));
  });

  test('keeps relative Mfuns images when normalizing quill content', () {
    final markdown = normalizeRichContent(
      '{"ops":[{"insert":{"image":"/static/article-image.jpg"}},'
      '{"insert":"\\n"}]}',
    );

    expect(
      markdown,
      contains('![图片](https://cdn2.mfuns.net/static/article-image.jpg)'),
    );
  });

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

  test('renders private-pack stickers inline instead of full-width images', () {
    final markdown = normalizeRichContent(
      '<p>太棒了<img class="sticker" width="50px" '
      'src="https://resource.mfuns.net/image/sticker/s/1.png" '
      "alt='[s-1]'/></p>",
    );
    expect(markdown, contains('![sticker:s-1]('));
    expect(markdown, isNot(contains('![图片](')));
    expect(markdown.trim().contains('\n\n'), isFalse);
  });

  test('derives sticker key from src when alt is missing', () {
    final markdown = normalizeRichContent(
      '<p>冲鸭<img class=\'sticker\' '
      'src="https://resource.mfuns.net/image/sticker/family/3.gif"/></p>',
    );
    expect(markdown, contains('![sticker:family-3]('));
  });

  test('keeps regular images as block images', () {
    final markdown = normalizeRichContent(
      '<p><img src="https://example.test/photo.jpg" alt="照片"/></p>',
    );
    expect(markdown, contains('![照片](https://example.test/photo.jpg)'));
    expect(markdown, isNot(contains('sticker:')));
  });

  test('converts quill json content with stickers to markdown', () {
    final markdown = normalizeRichContent(
      '{"ops":[{"insert":{"sticker":"simple-5"}},{"insert":"赞\\n"}]}',
    );
    expect(markdown, contains('![sticker:simple-5]('));
    expect(markdown, contains('赞'));
  });

  test('keeps article mentions as profile links', () {
    expect(
      normalizeRichContent(
        '{"ops":[{"insert":"你好 "},'
        '{"insert":{"mention":{"id":"38461","value":"少女乌斯"}}},'
        '{"insert":"\\n"}]}',
      ),
      '你好 [@少女乌斯](https://mfuns.net/member/38461)',
    );
    expect(
      normalizeRichContent(
        '<p>你好 <span class="mention" data-id="38461" '
        'data-value="少女乌斯">@少女乌斯</span></p>',
      ),
      '你好 [@少女乌斯](https://mfuns.net/member/38461)',
    );
    expect(
      normalizeRichContent('<p><a href="/member/38461">@少女乌斯</a></p>'),
      '[@少女乌斯](https://mfuns.net/member/38461)',
    );
  });

  testWidgets('article mention forwards its profile link on tap', (
    tester,
  ) async {
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichContentCard(
            source:
                '{"ops":[{"insert":{"mention":{"id":"38461","value":"少女乌斯"}}},{"insert":"\\n"}]}',
            onLinkTap: (url) => tapped = url,
          ),
        ),
      ),
    );

    await tester.tap(find.text('@少女乌斯'));
    expect(tapped, 'https://mfuns.net/member/38461');
  });

  test('keeps quoted article and video links from article HTML', () {
    final markdown = normalizeRichContent(
      '<p><a href="/article/108306">MA10830</a> '
      '<a href="/video/60482">MV60482</a> '
      '<a href="https://m.mfuns.net/member/83597">乙女椿</a></p>',
    );
    expect(markdown, contains('[MA10830](https://mfuns.net/article/108306)'));
    expect(markdown, contains('[MV60482](https://mfuns.net/video/60482)'));
    expect(markdown, contains('[乙女椿](https://m.mfuns.net/member/83597)'));
  });

  testWidgets('quoted MA and MV links are tappable in article content', (
    tester,
  ) async {
    final tapped = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RichContentCard(
            source:
                '<p><a href="/article/108306">MA10830</a></p>'
                '<p><a href="/video/60482">MV60482</a></p>',
            onLinkTap: tapped.add,
          ),
        ),
      ),
    );

    await tester.tap(find.text('MA10830'));
    await tester.tap(find.text('MV60482'));
    expect(tapped, [
      'https://mfuns.net/article/108306',
      'https://mfuns.net/video/60482',
    ]);
  });

  test('keeps quill inline and block formatting when opening an article', () {
    final markdown = normalizeRichContent(
      '{"ops":['
      '{"insert":"富文本","attributes":{"bold":true}},'
      '{"insert":"标题"},'
      '{"insert":"\\n","attributes":{"header":2}},'
      '{"insert":"项目一"},'
      '{"insert":"\\n","attributes":{"list":"bullet"}}'
      ']}',
    );
    expect(markdown, contains('## **富文本**标题'));
    expect(markdown, contains('- 项目一'));
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
