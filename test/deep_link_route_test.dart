import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/core/widgets/content_link_handler.dart';

void main() {
  testWidgets('pushMfunsTargetOnNavigator pushes a route for article links',
      (tester) async {
    final key = GlobalKey<NavigatorState>();
    final controller = AppController();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      home: const Scaffold(body: Text('home')),
    ));

    final navigator = key.currentState;
    expect(navigator, isNotNull);
    expect(navigator!.canPop(), isFalse);

    final target = parseMfunsLink('https://m.mfuns.net/article/122326');
    expect(target, isNotNull);
    expect(target!.type, 'article');
    expect(target.id, 122326);

    Object? error;
    try {
      pushMfunsTargetOnNavigator(navigator, controller, target);
    } catch (e) {
      error = e;
    }
    await tester.pump();

    expect(error, isNull, reason: 'pushMfunsTargetOnNavigator must not throw');
    expect(navigator.canPop(), isTrue,
        reason: 'deep link should push a new route onto the navigator');
  });

  test('parseMfunsLink handles mfuns.wgen.top and mfuns.net domains', () {
    final cases = <String, (String, int)>{
      'https://m.mfuns.net/video/60751': ('video', 60751),
      'https://www.mfuns.net/article/122326': ('article', 122326),
      'https://mfuns.wgen.top/article/122326': ('article', 122326),
      'https://mfuns.wgen.top/feed/273061': ('feed', 273061),
      'https://www.mfuns.wgen.top/video/60751': ('video', 60751),
    };
    cases.forEach((url, expected) {
      final target = parseMfunsLink(url);
      expect(target, isNotNull, reason: url);
      expect(target!.type, expected.$1, reason: url);
      expect(target.id, expected.$2, reason: url);
    });
  });
}
