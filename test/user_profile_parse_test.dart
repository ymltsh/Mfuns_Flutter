import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('derives the level from the badges list (real get_user schema)', () {
    final profile = UserProfile.fromJson({
      'id': 17627,
      'name': '微风与少年',
      'avatar': '/static/avatar.jpg',
      'gender': 0,
      'badges': [8, 20],
    });

    expect(profile.level, 8);
  });

  test('derives the level from badge objects with badge_id', () {
    final profile = UserProfile.fromJson({
      'id': 1,
      'name': '喵友',
      'badges': [
        {'badge_id': 3, 'expire_time': 0},
      ],
    });

    expect(profile.level, 3);
  });

  test('prefers an explicit level_id over the badges list', () {
    final profile = UserProfile.fromJson({
      'id': 1,
      'name': '喵友',
      'level_id': 9,
      'badges': [5],
    });

    expect(profile.level, 9);
  });

  test('leaves level null when no level badge is present', () {
    final profile = UserProfile.fromJson({
      'id': 1,
      'name': '喵友',
      'badges': [20],
    });

    expect(profile.level, isNull);
  });
}
