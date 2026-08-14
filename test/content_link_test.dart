import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
