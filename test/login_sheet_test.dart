import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/features/auth/login_sheet.dart';

void main() {
  testWidgets('login sheet switches between password and SMS forms',
      (tester) async {
    final controller = AppController();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showLoginSheet(context, controller),
            child: const Text('打开登录'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();
    expect(find.text('用户名 / ID / 邮箱 / 手机号'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);

    await tester.tap(find.text('验证码登录'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sms-login-phone')), findsOneWidget);
    expect(find.byKey(const ValueKey('sms-login-code')), findsOneWidget);
    expect(find.byKey(const ValueKey('sms-send-code')), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
  });

  testWidgets('SMS form validates phone before making a request',
      (tester) async {
    final controller = AppController();
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showLoginSheet(context, controller),
            child: const Text('打开登录'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('验证码登录'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('sms-login-phone')), '123');
    await tester.tap(find.text('获取验证码'));
    await tester.pump();

    expect(find.text('请输入正确的 11 位手机号'), findsOneWidget);
  });
}
