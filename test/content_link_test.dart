import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/widgets/content_link_handler.dart';
import 'package:mfuns_flutter/core/widgets/content_spans.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

Widget _host(List<CommentSpan> spans) => MaterialApp(
      home: Scaffold(
        body: ContentSpans(spans: spans),
      ),
    );

/// 找出带下划线（链接样式）的 Text 及其文本内容。
List<String> _linkTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((text) => text.style?.decoration == TextDecoration.underline)
    .map((text) => text.data ?? '')
    .toList();

void main() {
  testWidgets('renders http links as underlined tappable text', (tester) async {
    await tester.pumpWidget(_host([
      const CommentSpan.text('看看这个 https://www.mfuns.net/article/1 怎么样'),
    ]));
    expect(_linkTexts(tester), ['https://www.mfuns.net/article/1']);
    expect(find.textContaining('看看这个'), findsOneWidget);
    expect(find.textContaining('怎么样'), findsOneWidget);
  });

  testWidgets('strips trailing punctuation and keeps CJK text plain',
      (tester) async {
    await tester.pumpWidget(_host([
      const CommentSpan.text('链接：https://a.com/b/c，以及 www.example.com。'),
    ]));
    expect(_linkTexts(tester), ['https://a.com/b/c', 'www.example.com']);
    expect(find.textContaining('，以及'), findsOneWidget);
    expect(find.text('。'), findsOneWidget);
  });

  testWidgets('plain text without links renders unchanged', (tester) async {
    await tester.pumpWidget(_host([const CommentSpan.text('普通评论内容')]));
    expect(find.text('普通评论内容'), findsOneWidget);
    expect(_linkTexts(tester), isEmpty);
  });

  testWidgets('mixed sticker and link spans render together', (tester) async {
    await tester.pumpWidget(_host(const [
      CommentSpan.text('去 https://b.com/x 看看'),
      CommentSpan.sticker('s-1'),
    ]));
    expect(_linkTexts(tester), ['https://b.com/x']);
    expect(find.byIcon(Icons.emoji_emotions_outlined), findsOneWidget);
  });

  testWidgets('LinkText renders inline links with tap callback', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LinkText(
          text: '简介 https://www.mfuns.net/video/60751 结尾',
          onLinkTap: (url) => tapped = url,
        ),
      ),
    ));
    expect(find.textContaining('简介'), findsOneWidget);
    await tester.tap(find.textContaining('https://www.mfuns.net/video/60751'));
    expect(tapped, 'https://www.mfuns.net/video/60751');
  });

  testWidgets('ContentSpans forwards onLinkTap for links', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ContentSpans(
          spans: const [CommentSpan.text('看看 https://m.mfuns.net/article/122326')],
          onLinkTap: (url) => tapped = url,
        ),
      ),
    ));
    await tester.tap(find.text('https://m.mfuns.net/article/122326'));
    expect(tapped, 'https://m.mfuns.net/article/122326');
  });

  testWidgets('recognizes bare mv numbers as video links', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ContentSpans(
          spans: const [CommentSpan.text('安利 mv60751，好看！')],
          onLinkTap: (url) => tapped = url,
        ),
      ),
    ));
    expect(find.text('mv60751'), findsOneWidget);
    await tester.tap(find.text('mv60751'));
    expect(tapped, 'https://mfuns.net/mv60751');
  });

  testWidgets('mv numbers inside plain words are not links', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ContentSpans(
          spans: const [CommentSpan.text('himv60751x 不是链接')],
          onLinkTap: (url) => tapped = url,
        ),
      ),
    ));
    expect(find.text('himv60751x 不是链接'), findsOneWidget);
    expect(tapped, isNull);
  });

  testWidgets('LinkText recognizes bare mv numbers', (tester) async {
    String? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LinkText(
          text: '简介 mv60751 结尾',
          onLinkTap: (url) => tapped = url,
        ),
      ),
    ));
    await tester.tap(find.textContaining('mv60751'));
    expect(tapped, 'https://mfuns.net/mv60751');
  });

  test('parseMfunsLink covers all link formats', () {
    final cases = <String, (String, int)>{
      'mfuns://video/60751': ('video', 60751),
      'mfuns://article/122326': ('article', 122326),
      'mfuns://feed/273061': ('feed', 273061),
      'mfuns://mv60751': ('video', 60751),
      'https://mfuns.net/mv60751': ('video', 60751),
      'https://www.mfuns.net/video/60751': ('video', 60751),
      'https://m.mfuns.net/video/60751': ('video', 60751),
      'https://www.mfuns.net/article/122326': ('article', 122326),
      'https://m.mfuns.net/feed/273061': ('feed', 273061),
      'mv60751': ('video', 60751),
    };
    cases.forEach((url, expected) {
      final target = parseMfunsLink(url);
      expect(target, isNotNull, reason: url);
      expect(target!.type, expected.$1, reason: url);
      expect(target.id, expected.$2, reason: url);
    });

    expect(parseMfunsLink('https://example.com/video/1'), isNull);
    expect(parseMfunsLink('https://www.mfuns.net/video/abc'), isNull);
    expect(parseMfunsLink(''), isNull);
  });
}
