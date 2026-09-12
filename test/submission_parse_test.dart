import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('parses submission list items with status labels', () {
    final item = SubmissionItem.fromJson({
      'id': 99,
      'resource_id': 12345,
      'title': '测试投稿',
      'status': 1,
      'created_at': 1786000000,
      'cover': '/static/list-cover.jpg',
    });
    expect(item.id, 99);
    expect(item.resourceId, 12345);
    expect(item.title, '测试投稿');
    expect(item.status, 1);
    expect(item.statusLabel, '已发布');
    expect(item.createdAt, isNotNull);
    expect(item.cover, 'https://cdn2.mfuns.net/static/list-cover.jpg');
  });

  test('parses submission detail from a nested contribute object', () {
    final detail = SubmissionDetail.fromJson({
      'contribute': {
        'id': 99,
        'resource_id': 12345,
        'title': '深入理解 Flutter',
        'content': '<p>正文内容</p>',
        'content_format': 'html',
        'status': 2,
        'category_id': 44,
        'tags': ['Flutter', '教程'],
        'cover': '/static/cover.jpg',
        'videos': '[{"type":"direct","content":7788,"title":"第一集",'
            '"meta":{"duration":120},"transcode_status":1}]',
      },
    });
    expect(detail.id, 99);
    expect(detail.title, '深入理解 Flutter');
    expect(detail.content, '正文内容');
    expect(detail.statusLabel, '审核中');
    expect(detail.categoryId, 44);
    expect(detail.tags, ['Flutter', '教程']);
    expect(detail.cover, 'https://cdn2.mfuns.net/static/cover.jpg');
    expect(detail.rawContent, '<p>正文内容</p>');
    expect(detail.contentFormat, 'html');
    expect(detail.videos, hasLength(1));
    expect(detail.videos.single.content, 7788);
    expect(detail.videos.single.toJson(), {
      'transcode_status': 1,
      'type': 'direct',
      'content': 7788,
      'title': '第一集',
      'meta': {'duration': 120},
    });
  });

  test('maps all submission statuses to labels', () {
    expect(submissionStatusLabel(0), '草稿');
    expect(submissionStatusLabel(1), '已发布');
    expect(submissionStatusLabel(2), '审核中');
    expect(submissionStatusLabel(3), '驳回');
    expect(submissionStatusLabel(4), '被驳回修改');
    expect(submissionStatusLabel(5), '定时发布');
  });
}
