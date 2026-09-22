import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/widgets/player_more_overlay.dart';

void main() {
  testWidgets('uses a one-half right panel and merges volume with mute', (
    tester,
  ) async {
    var volume = .6;

    Widget build() => MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => PlayerMoreOverlay(
            volume: volume,
            speed: 1,
            onDismiss: () {},
            onVolumeChanged: (value) => setState(() => volume = value),
            onSpeedChanged: (_) {},
          ),
        ),
      ),
    );

    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(build());

    expect(
      tester.getSize(find.byKey(const ValueKey('player-more-panel'))).width,
      450,
    );
    expect(
      tester
          .widget<Material>(find.byKey(const ValueKey('player-more-material')))
          .color,
      const Color(0xff1d1d22),
    );
    expect(find.text('音量'), findsOneWidget);
    expect(find.text('静音'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('player-volume-toggle')));
    await tester.pump();
    expect(volume, 0);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('player-volume-toggle')));
    await tester.pump();
    expect(volume, .6);
  });

  testWidgets('embedded panel follows system light and dark themes', (
    tester,
  ) async {
    Widget build(ThemeData theme) => MaterialApp(
      theme: theme,
      home: Scaffold(
        body: PlayerMoreOverlay(
          presentation: PlayerMorePresentation.bottom,
          volume: .7,
          speed: 1,
          onDismiss: () {},
          onVolumeChanged: (_) {},
          onSpeedChanged: (_) {},
        ),
      ),
    );

    final light = ThemeData.light();
    await tester.pumpWidget(build(light));
    expect(
      tester
          .widget<Material>(find.byKey(const ValueKey('player-more-material')))
          .color,
      light.colorScheme.surface,
    );

    final dark = ThemeData.dark();
    await tester.pumpWidget(build(dark));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Material>(find.byKey(const ValueKey('player-more-material')))
          .color,
      dark.colorScheme.surface,
    );
  });

  testWidgets('uses a rounded bottom panel for embedded playback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: PlayerMoreOverlay(
              presentation: PlayerMorePresentation.bottom,
              volume: .7,
              speed: 1,
              onDismiss: () {},
              onVolumeChanged: (_) {},
              onSpeedChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('player-more-panel'))),
      const Size(400, 576),
    );
    expect(
      find.byKey(const ValueKey('player-more-drag-handle')),
      findsOneWidget,
    );
    expect(find.text('播放设置'), findsOneWidget);
  });

  testWidgets('groups mini player, system PiP and DLNA actions', (
    tester,
  ) async {
    var action = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerMoreOverlay(
            volume: .7,
            speed: 1,
            onDismiss: () {},
            onVolumeChanged: (_) {},
            onSpeedChanged: (_) {},
            onAppMiniPlayer: () => action = 'mini',
            onSystemPip: () => action = 'pip',
            onCast: () => action = 'cast',
          ),
        ),
      ),
    );

    expect(find.text('应用内小窗'), findsOneWidget);
    expect(find.text('系统画中画'), findsOneWidget);
    expect(find.text('DLNA 投屏'), findsOneWidget);

    await tester.tap(find.text('应用内小窗'));
    expect(action, 'mini');
    await tester.tap(find.text('系统画中画'));
    expect(action, 'pip');
    await tester.tap(find.text('DLNA 投屏'));
    expect(action, 'cast');
  });
}
