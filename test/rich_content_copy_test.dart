import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/content/article_text_copy_page.dart';
import 'package:mfuns_flutter/features/content/rich_content_card.dart';

void main() {
  test('rich content converts to readable plain text', () {
    const source = '<h1>标题</h1>'
        '<p>正文 <strong>重点</strong> <a href="https://example.com">链接</a></p>'
        '<ul><li>第一项</li><li>第二项</li></ul>'
        '<p><img src="https://example.com/a.png" alt="示意图"></p>';

    expect(
      richContentToPlainText(source),
      '标题\n\n正文 重点 链接\n\n• 第一项\n• 第二项\n\n[示意图]',
    );
  });

  testWidgets('mobile article opens dedicated copy page after long press',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: const Scaffold(
        body: RichContentCard(source: '<p>用于复制的正文</p>'),
      ),
    ));

    expect(find.byType(SelectableText), findsNothing);
    await tester.longPress(find.text('用于复制的正文'));
    await tester.pumpAndSettle();
    expect(find.text('复制文本'), findsOneWidget);

    await tester.tap(find.text('复制文本'));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleTextCopyPage), findsOneWidget);
    expect(find.byKey(const ValueKey('article-copy-text')), findsOneWidget);
    expect(find.text('用于复制的正文'), findsOneWidget);
  });

  testWidgets('dragging from mobile article text scrolls its parent',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: ListView(
            controller: controller,
            children: const [
              RichContentCard(
                source: '<p>从这段正文中央开始滑动</p><p>第二段正文</p>',
              ),
              SizedBox(height: 800),
            ],
          ),
        ),
      ),
    ));

    await tester.drag(find.text('从这段正文中央开始滑动'), const Offset(8, -180));
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
  });
}
