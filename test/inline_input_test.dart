import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/widgets/inline_emoji_input.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

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

  testWidgets('silently converts @name + space into a mention', (tester) async {
    final inputKey = GlobalKey<InlineEmojiInputState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineEmojiInput(
            key: inputKey,
            onSearchUser: (keyword) async => [
              UserProfile.fromJson({'id': 38461, 'name': keyword}),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '@少女乌斯 ');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final spans = inputKey.currentState!.spans;
    expect(spans, hasLength(1));
    expect(spans.first.isMention, isTrue);
    expect(spans.first.mentionId, '38461');
    expect(spans.first.mentionName, '少女乌斯');
  });

  testWidgets('does not trigger mention without the trailing space',
      (tester) async {
    final inputKey = GlobalKey<InlineEmojiInputState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineEmojiInput(
            key: inputKey,
            onSearchUser: (keyword) async => [
              UserProfile.fromJson({'id': 38461, 'name': keyword}),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '@少女乌斯');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final spans = inputKey.currentState!.spans;
    expect(spans.single.isMention, isFalse);
    expect(spans.single.text, '@少女乌斯');
  });

  testWidgets('keeps @name as plain text when search returns nothing',
      (tester) async {
    final inputKey = GlobalKey<InlineEmojiInputState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineEmojiInput(
            key: inputKey,
            onSearchUser: (keyword) async => const [],
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '@路人甲 ');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    final spans = inputKey.currentState!.spans;
    expect(spans.single.isMention, isFalse);
    expect(spans.single.text, '@路人甲');
  });
}
