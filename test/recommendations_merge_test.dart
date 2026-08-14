import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

ContentPreview _preview(int id, {int type = 0}) => ContentPreview(
      id: id,
      title: '标题 $id',
      summary: '',
      cover: '',
      author: '作者 $id',
      category: '',
      type: type,
      likes: 0,
      comments: 0,
      views: 0,
    );

List<int> _ids(List<ContentPreview> items) =>
    items.map((item) => item.id).toList();

void main() {
  test('refreshes prepend fresh recommendations to the current list', () {
    final merged = AppController.mergeRecommendations(
      [_preview(1), _preview(2)],
      [_preview(3), _preview(4)],
    );
    expect(_ids(merged), [1, 2, 3, 4]);
  });

  test('drops duplicate ids already present in the list', () {
    final merged = AppController.mergeRecommendations(
      [_preview(2), _preview(5)],
      [_preview(1), _preview(2), _preview(3)],
    );
    expect(_ids(merged), [2, 5, 1, 3]);
  });

  test('keeps items sharing an id but with different types', () {
    final merged = AppController.mergeRecommendations(
      [_preview(7, type: 1)],
      [_preview(7, type: 0)],
    );
    expect(merged.length, 2);
    expect(merged[0].type, 1);
    expect(merged[1].type, 0);
  });

  test('keeps all id-0 items without deduplication', () {
    final merged = AppController.mergeRecommendations(
      [_preview(0)],
      [_preview(0)],
    );
    expect(merged.length, 2);
  });

  test('caps the list at 100 and drops the oldest entries', () {
    final fresh = List.generate(10, (i) => _preview(1000 + i));
    final existing = List.generate(95, (i) => _preview(i));
    final merged =
        AppController.mergeRecommendations(fresh, existing);

    expect(merged.length, AppController.maxRecommendations);
    expect(merged.first.id, 1000);
    expect(merged.last.id, 89);
    expect(_ids(merged), containsAll(List.generate(10, (i) => 1000 + i)));
  });
}
