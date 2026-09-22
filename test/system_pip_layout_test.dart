import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/video/floating_video_overlay.dart';

void main() {
  testWidgets('keeps the current app subtree mounted while PiP is active', (
    tester,
  ) async {
    var disposals = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SystemPipLayout(
          active: false,
          video: const ColoredBox(color: Colors.black),
          child: _DisposeProbe(onDispose: () => disposals++),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SystemPipLayout(
          active: true,
          video: const ColoredBox(color: Colors.black),
          child: _DisposeProbe(onDispose: () => disposals++),
        ),
      ),
    );

    expect(disposals, 0);
    expect(find.byType(_DisposeProbe), findsOneWidget);
  });
}

class _DisposeProbe extends StatefulWidget {
  const _DisposeProbe({required this.onDispose});

  final VoidCallback onDispose;

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
