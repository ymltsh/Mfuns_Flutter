import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 文章页 Stack + 拖动滑块结构的回归测试：
/// 首帧构建时位置已挂载但未完成布局（haveDimensions 为 false），
/// 滑块必须静默返回，不能访问 maxScrollExtent 抛错拖垮整页。
void main() {
  testWidgets('stack with listview and positioned slider works', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              children: [
                for (var i = 0; i < 60; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('第 $i 行内容内容内容内容内容内容内容内容'),
                  ),
              ],
            ),
            _FakeSlider(controller: controller),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);

    // 滚动后滑块可见，页面保持可滚动无异常。
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _FakeSlider extends StatefulWidget {
  const _FakeSlider({required this.controller});
  final ScrollController controller;
  @override
  State<_FakeSlider> createState() => _FakeSliderState();
}

class _FakeSliderState extends State<_FakeSlider> {
  var _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!_visible) setState(() => _visible = true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.hasClients) return const SizedBox.shrink();
    if (!controller.position.haveDimensions) return const SizedBox.shrink();
    final maxExtent = controller.position.maxScrollExtent;
    if (maxExtent <= 0) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final trackTop = MediaQuery.paddingOf(context).top + kToolbarHeight + 14;
    final trackBottom = MediaQuery.paddingOf(context).bottom + 22;
    final trackHeight = size.height - trackTop - trackBottom;
    final fraction =
        (controller.position.pixels / maxExtent).clamp(0.0, 1.0);
    final thumbHeight = trackHeight * 0.3;

    return Positioned(
      top: trackTop,
      right: 3,
      width: 26,
      height: trackHeight,
      child: IgnorePointer(
        ignoring: !_visible,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) => controller
                .jumpTo((details.localPosition.dy / trackHeight).clamp(0.0, 1.0) *
                    maxExtent),
            child: Stack(
              children: [
                Center(
                  child: SizedBox(width: 3, height: trackHeight),
                ),
                Positioned(
                  top: fraction * (trackHeight - thumbHeight),
                  left: 0,
                  right: 0,
                  child: Container(height: thumbHeight),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
