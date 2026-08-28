import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/app/mfuns_app.dart';

void main() {
  testWidgets('renders the primary navigation', (tester) async {
    await tester.pumpWidget(MfunsApp(controller: AppController()));

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('动态'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
  });
}
