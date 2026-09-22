import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/mfuns_api_client.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

class _FakeApiClient extends MfunsApiClient {
  final requests = <(String, Map<String, Object?>)>[];

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    requests.add((path, query));
    if (path == '/v1/tag/article_list') {
      return const ApiResponse(
        code: 1,
        message: '成功',
        data: [
          {'id': 10, 'last_id': 100, 'title': '标签文章'},
        ],
      );
    }
    if (path == '/v1/tag/video_list') {
      return const ApiResponse(
        code: 1,
        message: '成功',
        data: [
          {'id': 20, 'last_id': 200, 'title': '标签视频'},
        ],
      );
    }
    fail('unexpected path: $path');
  }
}

void main() {
  test('tag contents merge article and video pages', () async {
    final client = _FakeApiClient();
    final repository = HomeRepository(client);

    final result = await repository.getTagContents(
      '游戏',
      articleLastId: 9,
      videoLastId: 19,
      size: 1,
    );

    expect(client.requests.map((request) => request.$1), [
      '/v1/tag/article_list',
      '/v1/tag/video_list',
    ]);
    expect(client.requests[0].$2, {'tag': '游戏', 'last_id': 9, 'size': 1});
    expect(client.requests[1].$2, {'tag': '游戏', 'last_id': 19, 'size': 1});
    expect(result.items.map((item) => (item.id, item.type)).toSet(), {
      (10, 0),
      (20, 1),
    });
    expect(result.articleLastId, 100);
    expect(result.videoLastId, 200);
    expect(result.hasMoreArticles, isTrue);
    expect(result.hasMoreVideos, isTrue);
    expect(result.hasMore, isTrue);
  });

  test('tag contents stop after both resource types reach the end', () async {
    final repository = HomeRepository(_FakeApiClient());

    final result = await repository.getTagContents('动画', size: 50);

    expect(result.hasMore, isFalse);
  });
}
