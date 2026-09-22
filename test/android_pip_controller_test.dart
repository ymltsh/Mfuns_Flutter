import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/media/android_pip_controller.dart';

void main() {
  test('PiP entering state switches the root to the video surface', () {
    final controller = AndroidPipController.instance;
    addTearDown(() => controller.debugSetActive(false));

    controller.debugSetEntering(true);

    expect(controller.isEntering, isTrue);
    expect(controller.shouldShowVideoSurface, isTrue);

    controller.debugSetActive(true);
    expect(controller.isEntering, isFalse);
    expect(controller.shouldShowVideoSurface, isTrue);
  });
}
