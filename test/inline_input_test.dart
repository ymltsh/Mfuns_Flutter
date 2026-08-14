import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/widgets/inline_emoji_input.dart';

void main() {
  testWidgets('InlineEmojiInput renders without layout exceptions',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: InlineEmojiInput(hintText: '说点什么…'),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('说点什么…'), findsOneWidget);
  });

  testWidgets('InlineEmojiInput accepts typed text without exceptions',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: InlineEmojiInput(hintText: '说点什么…'),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '一段文字');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('一段文字'), findsOneWidget);
  });

  testWidgets('InlineEmojiInput in a narrow row never overflows',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: InlineEmojiInput(hintText: '说点什么…'),
          ),
        ),
      ),
    );
    await tester.enterText(
        find.byType(TextField), '很长的一段文字很长的一段文字很长的一段文字很长的一段文字很长的一段文字');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
