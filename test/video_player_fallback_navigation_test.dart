import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';
import 'package:mfuns_flutter/features/video/content_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('player keeps navigation visible before media is available',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    final controller = AppController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MfunsVideoPlayer(
          controller: controller,
          videoId: 1,
          title: '无法加载的视频',
          coverUrl: '',
          qualities: const [
            VideoQuality(
              part: 1,
              name: '720p',
              label: '720p',
              url: 'https://example.invalid/video.mp4',
            ),
          ],
        ),
      ),
    ));

    expect(
      find.byKey(const ValueKey('video-player-fallback-header')),
      findsOneWidget,
    );
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byTooltip('返回首页'), findsOneWidget);
    expect(find.textContaining('无法加载的视频'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
