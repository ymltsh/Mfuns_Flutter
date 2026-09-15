import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/theme/app_theme.dart';

void main() {
  test('edge-to-edge 样式保持导航栏透明并随主题切换手势条颜色', () {
    final light = appSystemUiOverlayStyle(brightness: Brightness.light);
    final dark = appSystemUiOverlayStyle(brightness: Brightness.dark);

    expect(light.systemNavigationBarColor, Colors.transparent);
    expect(light.systemNavigationBarDividerColor, Colors.transparent);
    expect(light.systemNavigationBarContrastEnforced, isFalse);
    expect(light.systemNavigationBarIconBrightness, Brightness.dark);
    expect(dark.systemNavigationBarIconBrightness, Brightness.light);
  });
}
