import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/features/video/content_detail_page.dart';

void main() {
  testWidgets('评论输入框从圆形按钮平滑展开且保持可见', (tester) async {
    await tester.pumpWidget(const _ComposerHost());

    final surface = find.byKey(const ValueKey('comment-composer-surface'));
    final clip = find.byKey(const ValueKey('comment-composer-clip'));
    final send = find.byKey(const ValueKey('comment-composer-send'));
    expect(surface, findsOneWidget);
    expect(commentComposerFabVisibility.isVisible, isTrue);
    final collapsedBounds = _clipBounds(tester, clip);
    expect(collapsedBounds.width, lessThan(70));
    expect(collapsedBounds.height, lessThan(70));
    final collapsedCenter = tester.getTopLeft(clip) + collapsedBounds.center;
    expect((tester.getCenter(send) - collapsedCenter).distance, lessThan(0.01));
    expect(tester.getSize(send), const Size.square(48));

    await tester.tap(find.byTooltip('展开评论输入框'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));

    final transitioningWidth = _clipBounds(tester, clip).width;
    expect(transitioningWidth, greaterThan(56));
    expect(transitioningWidth, lessThan(760));

    await tester.pumpAndSettle();
    expect(commentComposerFabVisibility.isVisible, isFalse);
    expect(_clipBounds(tester, clip).width, 760);
    expect(find.text('说点什么…'), findsOneWidget);
    expect(find.byTooltip('折叠评论输入框'), findsNothing);

    tester.state<_ComposerHostState>(find.byType(_ComposerHost)).collapse();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(commentComposerFabVisibility.isVisible, isTrue);
    final recollapsedBounds = _clipBounds(tester, clip);
    final recollapsedCenter =
        tester.getTopLeft(clip) + recollapsedBounds.center;
    expect(
      (tester.getCenter(send) - recollapsedCenter).distance,
      lessThan(0.01),
    );
    expect(tester.getSize(send), const Size.square(48));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(commentComposerFabVisibility.isVisible, isFalse);
  });
}

Rect _clipBounds(WidgetTester tester, Finder finder) {
  final widget = tester.widget<ClipPath>(finder);
  final clipper = widget.clipper!;
  return clipper.getClip(tester.getSize(finder)).getBounds();
}

class _ComposerHost extends StatefulWidget {
  const _ComposerHost();

  @override
  State<_ComposerHost> createState() => _ComposerHostState();
}

class _ComposerHostState extends State<_ComposerHost> {
  final _controller = AppController();
  var _collapsed = true;

  void collapse() => setState(() => _collapsed = true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CommentComposerBar(
              controller: _controller,
              areaId: 1,
              collapsed: _collapsed,
              onExpand: () => setState(() => _collapsed = false),
              onSubmitted: () {},
            ),
          ),
        ],
      ),
    ),
  );
}
