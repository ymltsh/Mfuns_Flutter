import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/media/player_viewport.dart';

void main() {
  group('calculatePortraitPlayerViewport', () {
    test('普通 16:9 视频使用自然高度', () {
      final result = calculatePortraitPlayerViewport(
        viewportWidth: 360,
        screenHeight: 800,
        videoAspectRatio: 16 / 9,
      );

      expect(result.surfaceHeight, closeTo(202.5, .001));
      expect(result.videoWidth, closeTo(360, .001));
      expect(result.videoHeight, closeTo(202.5, .001));
    });

    test('极宽视频保留 16:9 控制视口并上下居中', () {
      final result = calculatePortraitPlayerViewport(
        viewportWidth: 360,
        screenHeight: 800,
        videoAspectRatio: 8,
      );

      expect(result.surfaceHeight, closeTo(202.5, .001));
      expect(result.videoWidth, closeTo(360, .001));
      expect(result.videoHeight, closeTo(45, .001));
    });

    test('极高视频使用 4:3 控制视口并左右居中', () {
      final result = calculatePortraitPlayerViewport(
        viewportWidth: 360,
        screenHeight: 800,
        videoAspectRatio: .25,
      );

      expect(result.surfaceHeight, closeTo(270, .001));
      expect(result.videoWidth, closeTo(67.5, .001));
      expect(result.videoHeight, closeTo(270, .001));
    });

    test('矮屏设备不会超过屏幕高度的一半', () {
      final result = calculatePortraitPlayerViewport(
        viewportWidth: 360,
        screenHeight: 360,
        videoAspectRatio: .5,
      );

      expect(result.surfaceHeight, closeTo(180, .001));
      expect(result.videoHeight, closeTo(180, .001));
    });

    test('无效比例回退到 16:9', () {
      final result = calculatePortraitPlayerViewport(
        viewportWidth: 360,
        screenHeight: 800,
        videoAspectRatio: 0,
      );

      expect(result.surfaceHeight, closeTo(202.5, .001));
      expect(result.videoWidth, closeTo(360, .001));
    });
  });
}
