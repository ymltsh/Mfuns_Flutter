import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';
import 'package:mfuns_flutter/features/video/content_detail_page.dart';

void main() {
  CommunityComment comment(int id) => CommunityComment(
        id: id,
        userId: id,
        authorName: '用户 $id',
        avatar: '',
        content: '回复 $id',
        spans: const [],
        images: const [],
        likes: 0,
        liked: false,
        replyCount: 0,
        createdAt: null,
      );

  test('merges reply pages beyond the first 20 and removes duplicates', () {
    final firstPage =
        List.generate(20, (index) => comment(index + 1), growable: false);
    final secondPage = [
      comment(20),
      ...List.generate(5, (i) => comment(i + 21))
    ];

    final merged = mergeCommentReplyPages(firstPage, secondPage);

    expect(merged, hasLength(25));
    expect(merged.map((item) => item.id).toSet(), hasLength(25));
    expect(merged.last.id, 25);
  });

  test('deleting from a fixed-length reply list uses a replacement list', () {
    final replies =
        List.generate(20, (index) => comment(index + 1), growable: false);

    final remaining = removeCommentReply(replies, 7);

    expect(remaining, hasLength(19));
    expect(remaining.any((item) => item.id == 7), isFalse);
    expect(replies, hasLength(20));
  });
}
