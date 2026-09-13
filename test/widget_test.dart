import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/app/mfuns_app.dart';
import 'package:mfuns_flutter/core/config/app_config.dart';
import 'package:mfuns_flutter/core/config/user_preferences.dart';
import 'package:mfuns_flutter/core/theme/app_theme.dart';
import 'package:mfuns_flutter/features/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders the primary navigation', (tester) async {
    await tester.pumpWidget(MfunsApp(controller: AppController()));

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('动态'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
  });

  testWidgets('我的页面按场景整理访客入口', (tester) async {
    final controller = AppController();
    await tester.pumpWidget(MfunsApp(controller: controller));

    await tester.tap(find.text('我的'));
    await tester.pump();

    expect(find.text('内容与下载'), findsOneWidget);
    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('下载管理'), findsOneWidget);
    expect(find.text('需登录'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('profile-action-list')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('profile-action-grid')), findsNothing);

    await controller.setProfileEntryLayout(ProfileEntryLayout.card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('profile-action-list')), findsNothing);
    expect(find.byKey(const ValueKey('profile-action-grid')), findsNWidgets(2));
  });

  testWidgets('深浅色切换会立即更新按钮选中状态', (tester) async {
    await tester.pumpWidget(MfunsApp(controller: AppController()));
    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.ensureVisible(find.text('主题外观'));
    await tester.tap(find.text('主题外观'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('深色'));
    await tester.pump();
    var button = tester.widget<SegmentedButton<AppThemeMode>>(
      find.byType(SegmentedButton<AppThemeMode>),
    );
    expect(button.selected, {AppThemeMode.dark});

    await tester.tap(find.text('浅色'));
    await tester.pump();
    button = tester.widget<SegmentedButton<AppThemeMode>>(
      find.byType(SegmentedButton<AppThemeMode>),
    );
    expect(button.selected, {AppThemeMode.light});
  });

  testWidgets('设置页可切换我的页面入口样式', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = AppController();
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(controller: controller)),
    );
    await tester.pump();

    expect(find.text('账号与界面'), findsOneWidget);
    expect(find.text('播放与阅读'), findsOneWidget);
    expect(find.text('下载与网络'), findsOneWidget);
    expect(find.text('应用与支持'), findsOneWidget);
    expect(find.text('编辑资料'), findsOneWidget);
    expect(find.text('播放器配置'), findsOneWidget);
    expect(find.text('网络诊断'), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);

    var button = tester.widget<SegmentedButton<ProfileEntryLayout>>(
      find.byType(SegmentedButton<ProfileEntryLayout>),
    );
    expect(button.selected, {ProfileEntryLayout.list});

    await tester.tap(find.text('卡片'));
    await tester.pump();
    button = tester.widget<SegmentedButton<ProfileEntryLayout>>(
      find.byType(SegmentedButton<ProfileEntryLayout>),
    );
    expect(button.selected, {ProfileEntryLayout.card});
    expect(controller.profileEntryLayout, ProfileEntryLayout.card);
  });

  testWidgets('连续点击关于 Logo 七次解锁版本星座彩蛋', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(controller: AppController())),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('关于'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();

    final logo = find.byKey(const ValueKey('about-logo-easter-egg'));
    expect(logo, findsOneWidget);
    for (var i = 0; i < 7; i++) {
      await tester.tap(logo);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();

    expect(
        find.byKey(const ValueKey('constellation-codename')), findsOneWidget);
    expect(find.text('仙后座'), findsOneWidget);
    expect(find.text('CAS'), findsOneWidget);
    expect(
      find.textContaining('v${AppConfig.appVersion} (${AppConfig.appBuild})'),
      findsOneWidget,
    );
  });
}
