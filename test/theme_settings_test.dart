import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('应用背景默认使用网格与适中的图片不透明度', () async {
    expect(await ThemeSettings.loadBackgroundImage(), isEmpty);
    expect(
      await ThemeSettings.loadBackgroundOpacity(),
      ThemeSettings.defaultBackgroundOpacity,
    );
  });

  test('应用背景图片与不透明度可持久化并限制合法范围', () async {
    await ThemeSettings.saveBackgroundImage(r'C:\images\background.png');
    await ThemeSettings.saveBackgroundOpacity(1.5);

    expect(
      await ThemeSettings.loadBackgroundImage(),
      r'C:\images\background.png',
    );
    expect(await ThemeSettings.loadBackgroundOpacity(), 1);

    await ThemeSettings.saveBackgroundImage('');
    await ThemeSettings.saveBackgroundOpacity(-1);
    expect(await ThemeSettings.loadBackgroundImage(), isEmpty);
    expect(await ThemeSettings.loadBackgroundOpacity(), 0);
  });
}
