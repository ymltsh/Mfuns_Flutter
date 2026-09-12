import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  Map<String, dynamic> historyItem({
    required int id,
    required Object time,
    int type = 0,
  }) =>
      {
        'time': time,
        'resource_info': {
          'id': id,
          'title': '内容 $id',
          'type': type,
        },
      };

  test('extracts the cursor from a history list inside an object', () {
    final page = HistoryPage.fromData({
      'list': [
        historyItem(id: 2, time: '1788156396.257'),
        historyItem(id: 1, time: '1788156395.257'),
      ],
    });

    expect(page.items.map((item) => item.id), [2, 1]);
    expect(page.nextStartTime, '1788156395.257');
    expect(page.hasMore, isTrue);
  });

  test('preserves a large numeric start_time without double conversion', () {
    final page = HistoryPage.fromData({
      'data': {
        'list': [historyItem(id: 1, time: 1788156395257)],
      },
    });

    expect(page.nextStartTime, '1788156395257');
  });

  test('respects an explicit cursor and has_more flag', () {
    final page = HistoryPage.fromData({
      'list': [historyItem(id: 1, time: 100)],
      'next_start_time': '99.5',
      'has_more': 0,
      'total': 42,
    });

    expect(page.nextStartTime, '99.5');
    expect(page.hasMore, isFalse);
    expect(page.total, 42);
  });
}
