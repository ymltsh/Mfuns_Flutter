import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('parses sign info with numeric day lists', () {
    final info = SignInfo.fromJson({
      'list': [1, 3, 5, 8],
      'month_times': 4,
      'all_times': 1065,
    });
    expect(info.signedDays, [1, 3, 5, 8]);
    expect(info.monthTimes, 4);
    expect(info.allTimes, 1065);
  });

  test('parses the real per-day status array from sign_list', () {
    // 服务端返回 1 索引的每日状态数组：list[0] 为占位，list[i]="1" 表示
    // 第 i 天已签到（与 Web 端 sign[day] 一致），31 天月份长度为 32。
    final list = List.generate(32, (_) => '0');
    for (final day in [2, 4, 6, 7, 15]) {
      list[day] = '1';
    }
    final info = SignInfo.fromJson({
      'list': list,
      'month_times': 5,
      'all_times': 124,
    });
    expect(info.signedDays, [2, 4, 6, 7, 15]);
    expect(info.monthTimes, 5);
    expect(info.allTimes, 124);
  });

  test('parses sign info with date-string day lists', () {
    final info = SignInfo.fromJson({
      'list': ['2026-08-01', '2026-08-03', '2026-08-10'],
    });
    expect(info.signedDays, [1, 3, 10]);
    expect(info.monthTimes, 0);
    expect(info.allTimes, 0);
  });

  test('parses a sign rank entry from the real API shape', () {
    final entry = SignRankEntry.fromJson({
      'user': {
        'id': 17627,
        'name': '微风与少年',
        'name_color': 'red',
        'avatar': '/static/avatar.jpg',
        'badges': [8, 20],
      },
      'time': 1786636800,
      'count': 1065,
    });
    expect(entry.userId, 17627);
    expect(entry.name, '微风与少年');
    expect(entry.nameColor, 'red');
    expect(entry.avatar, 'https://cdn2.mfuns.net/static/avatar.jpg');
    expect(entry.count, 1065);
    expect(entry.signedAt, isNotNull);
  });

  test('parses an accumulated award', () {
    final award = SignAward.fromJson({'desc': '5 经验', 'type': 'exp'});
    expect(award.desc, '5 经验');
    expect(award.type, 'exp');
  });

  test('parses a level section from the real API shape', () {
    final section =
        LevelSection.fromJson({'id': 6, 'experience': 1800, 'level_id': 6});
    expect(section.levelId, 6);
    expect(section.experience, 1800);
  });
}
