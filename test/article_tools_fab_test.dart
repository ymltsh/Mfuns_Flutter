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
            children: const [SizedBox(height: 4000)],
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: ArticleToolsFab(controller: controller),
          ),
        ],
      ),
    ),
  );

  testWidgets('article tools jump to the start and end', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(buildSubject(controller));

    expect(find.byKey(const ValueKey('article-tools-start')), findsNothing);
    expect(find.byKey(const ValueKey('article-tools-end')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('article-tools-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('article-tools-end')));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.tap(find.byKey(const ValueKey('article-tools-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('article-tools-start')));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.minScrollExtent);
  });

  testWidgets('article tools follow theme colors and can be dragged', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Stack(
            children: [
              ListView(
                controller: controller,
                children: const [SizedBox(height: 4000)],
              ),
              Positioned.fill(
                child: ArticleToolsOverlay(
                  controller: controller,
                  minimumBottom: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final fab = find.byKey(const ValueKey('article-tools-fab'));
    final before = tester.getCenter(fab);
    expect(
      tester.widget<FloatingActionButton>(fab).backgroundColor,
      theme.colorScheme.primaryContainer,
    );

    await tester.drag(fab, const Offset(-120, -140));
    await tester.pumpAndSettle();
    final after = tester.getCenter(fab);

    expect(after.dx, lessThan(before.dx));
    expect(after.dy, lessThan(before.dy));
  });
}
