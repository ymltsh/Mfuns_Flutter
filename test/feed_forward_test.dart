import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/features/feed/feed_compose_page.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

void main() {
  test('转发请求使用 Quill JSON 并携带文章资源信息', () {
    final payload = buildFeedForwardPayload(
      content: 'QWQ',
      resourceId: 122971,
      resourceType: 0,
    );

    expect(payload['resource_id'], 122971);
    expect(payload['resource_type'], 0);
    expect(jsonDecode(payload['content']! as String), {
      'ops': [
        {'insert': 'QWQ\n'},
      ],
    });
  });

  test('转发支持文章、视频和动态，拒绝未知资源类型', () {
    for (final type in [0, 1, 3]) {
      expect(
        () => buildFeedForwardPayload(
          content: '转发理由',
          resourceId: 1,
          resourceType: type,
        ),
        returnsNormally,
      );
    }
    expect(
      () => buildFeedForwardPayload(
        content: '转发理由',
        resourceId: 1,
        resourceType: 4,
      ),
      throwsArgumentError,
    );
  });

  testWidgets('转发页展示资源并阻止空内容提交', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FeedForwardPage(
        controller: AppController(),
        resourceId: 122971,
        resourceType: 1,
        resourceTitle: '测试视频',
      ),
    ));

    expect(find.text('测试视频'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('feed-forward-submit')));
    await tester.pump();
    expect(find.text('说点什么吧'), findsOneWidget);
  });
}
