import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/video/content_detail_page.dart';

void main() {
  Widget buildSubject(ScrollController controller) => MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ListView(
                controller: controller,
                children: const [SizedBox(height: 2400)],
              ),
              ArticleProgressSlider(controller: controller),
            ],
          ),
        ),
      );

  testWidgets('custom slider suppresses the automatic desktop scrollbar',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: ArticleReaderScrollScope(
        disableAutomaticScrollbar: true,
        child: ListView(
          controller: controller,
          children: const [SizedBox(height: 2400)],
        ),
      ),
    ));

    expect(find.byType(Scrollbar), findsNothing);
  });

  testWidgets('desktop scrollbar remains when custom slider is disabled',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: ArticleReaderScrollScope(
        disableAutomaticScrollbar: false,
        child: ListView(
          controller: controller,
          children: const [SizedBox(height: 2400)],
        ),
      ),
    ));

    expect(find.byType(Scrollbar), findsOneWidget);
  });

  testWidgets('thumb reaches the bottom edge at 100 percent', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(buildSubject(controller));

    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    final viewport = tester.getRect(find.byType(Stack).first);
    final thumb = tester.getRect(
      find.byKey(const ValueKey('article-progress-thumb')),
    );
    expect(thumb.bottom, closeTo(viewport.bottom - 1, 0.1));
  });

  testWidgets('thumb drag advances smoothly without an initial jump',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(buildSubject(controller));

    controller.jumpTo(controller.position.maxScrollExtent * 0.4);
    await tester.pump();
    final before = controller.offset;
    final thumb = find.byKey(const ValueKey('article-progress-thumb-hit'));
    final gesture = await tester.startGesture(tester.getCenter(thumb));
    await gesture.moveBy(const Offset(0, 1));
    await tester.pump();

    // 第一帧只应产生同方向的小幅移动，不能因局部坐标变化向上跳动。
    expect(controller.offset, greaterThanOrEqualTo(before));
    expect(controller.offset - before, lessThan(10));

    await gesture.moveBy(const Offset(0, 80));
    await tester.pump();
    expect(controller.offset, greaterThan(before));
    expect(
        find.byKey(const ValueKey('article-progress-label')), findsOneWidget);
    await gesture.up();
  });
}
