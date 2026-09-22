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

  test('详情页评论输入框默认收纳并可持久化完整显示设置', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await UserPreferences.loadFullCommentInput(), isFalse);

    await UserPreferences.saveFullCommentInput(true);
    expect(await UserPreferences.loadFullCommentInput(), isTrue);
  });

  test('文章工具按钮默认关闭并可持久化开启设置', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await UserPreferences.loadArticleToolsFab(), isFalse);

    await UserPreferences.saveArticleToolsFab(true);
    expect(await UserPreferences.loadArticleToolsFab(), isTrue);
  });
}
