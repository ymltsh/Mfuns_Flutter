import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

Widget _host(List<CommentSpan> spans, String content) => MaterialApp(
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (spans.isEmpty)
              Text(content.isEmpty ? '（该评论没有文本内容）' : content)
            else
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 2,
                runSpacing: 4,
                children: spans
                    .map((span) => span.isSticker
                        ? const SizedBox(
                            width: 42, height: 42, child: Placeholder())
                        : Text(span.text,
                            style: const TextStyle(
                                color: Colors.blueGrey, height: 1.4)))
                    .toList(),
              ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('comment with text and sticker renders visible content',
      (tester) async {
    final comment = CommunityComment.fromJson({
      'id': 1,
      'user_id': 7,
      'content':
          "<p>HELLO</p><p>_............<img class='sticker' width='50px' src='https://resource.mfuns.net/image/sticker/s/1.png' alt='[s-1]'/></p>",
    });
    await tester.pumpWidget(_host(comment.spans, comment.content));
    expect(find.textContaining('HELLO'), findsOneWidget);
  });

  testWidgets('quill text comment renders', (tester) async {
    final comment = CommunityComment.fromJson({
      'id': 2,
      'user_id': 7,
      'content': '{"ops":[{"insert":"1111\\n"}]}',
    });
    await tester.pumpWidget(_host(comment.spans, comment.content));
    expect(find.textContaining('1111'), findsOneWidget);
  });

  testWidgets('sticker-only comment still shows the sticker placeholder',
      (tester) async {
    final comment = CommunityComment.fromJson({
      'id': 3,
      'user_id': 7,
      'content': '{"ops":[{"insert":{"sticker":"s-1"}},{"insert":"\\n"}]}',
    });
    await tester.pumpWidget(_host(comment.spans, comment.content));
    expect(find.byType(Placeholder), findsOneWidget);
  });
}
