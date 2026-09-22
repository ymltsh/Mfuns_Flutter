import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';
import 'package:mfuns_flutter/features/video/floating_video_controller.dart';
import 'package:mfuns_flutter/features/video/floating_video_overlay.dart';
import 'package:video_player/video_player.dart';

void main() {
  testWidgets('mini-player controls auto-hide and reappear on tap', (
    tester,
  ) async {
    final player = VideoPlayerController.networkUrl(
      Uri.parse('https://example.com/video.mp4'),
    );
    player.value = const VideoPlayerValue(
      duration: Duration(minutes: 1),
      size: Size(320, 180),
    );
    const preview = ContentPreview(
      id: 1,
      title: '视频',
      summary: '',
      cover: '',
      author: '',
      category: '',
      type: 1,
      likes: 0,
      comments: 0,
      views: 0,
    );
    const quality = VideoQuality(
      part: 1,
      name: '默认',
      label: '默认',
      url: 'https://example.com/video.mp4',
    );
    final floating = FloatingVideoController.instance;
    floating.attach(
      FloatingVideoSession(player: player, preview: preview, quality: quality),
    );
    floating.startFloating(player);
    addTearDown(() async {
      floating.takeFor(preview.id);
      floating.detach(player);
      await player.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FloatingVideoOverlay(
                onExpand: () {},
                controlsHideDelay: const Duration(milliseconds: 50),
              ),
            ],
          ),
        ),
      ),
    );

    AnimatedOpacity controls() => tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('floating-video-controls')),
    );

    expect(controls().opacity, 1);
    await tester.pump(const Duration(milliseconds: 60));
    expect(controls().opacity, 0);

    await tester.tap(find.byKey(const ValueKey('floating-video-player')));
    await tester.pump();
    expect(controls().opacity, 1);
  });
}
