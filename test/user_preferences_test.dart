import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/config/user_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('后台通知服务默认开启并可持久化', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await UserPreferences.loadBackgroundNotifications(), isTrue);

    await UserPreferences.saveBackgroundNotifications(false);
    expect(await UserPreferences.loadBackgroundNotifications(), isFalse);
  });

  test('我的页面入口样式默认为列表并可持久化', () async {
    SharedPreferences.setMockInitialValues({});

    expect(
      await UserPreferences.loadProfileEntryLayout(),
      ProfileEntryLayout.list,
    );

    await UserPreferences.saveProfileEntryLayout(ProfileEntryLayout.card);
    expect(
      await UserPreferences.loadProfileEntryLayout(),
      ProfileEntryLayout.card,
    );
  });
}
