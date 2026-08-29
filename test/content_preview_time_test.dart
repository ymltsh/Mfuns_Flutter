import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('parses content preview publish time from created_at', () {
    final preview = ContentPreview.fromJson({
      'id': 100,
      'title': '测试文章',
      'created_at': '2026-08-11 10:00:00',
    });
    expect(preview.createdAt, DateTime(2026, 8, 11, 10, 0));
  });

  test('parses content preview publish time from unix seconds', () {
    final preview = ContentPreview.fromJson({
      'id': 100,
      'title': '测试视频',
      'type': 1,
      'time': 1786000000,
    });
    expect(preview.createdAt, isNotNull);
    expect(preview.createdAt!.millisecondsSinceEpoch, 1786000000 * 1000);
  });

  test('leaves publish time null when missing', () {
    final preview = ContentPreview.fromJson({
      'id': 100,
      'title': '无时间',
    });
    expect(preview.createdAt, isNull);
  });
}
