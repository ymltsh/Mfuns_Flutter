import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/mfuns_api_client.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

class _FakeApiClient extends MfunsApiClient {
  String? requestedPath;
  Map<String, Object?>? requestedQuery;
  ApiResponse response = const ApiResponse(
    code: 1,
    message: '成功',
    data: {'list': <Object>[], 'total': 0},
  );

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    requestedPath = path;
    requestedQuery = query;
    return response;
  }
}

void main() {
  test('content search sends paging, field and sort filters', () async {
    final client = _FakeApiClient()
      ..response = const ApiResponse(
        code: 1,
        message: '成功',
        data: {
          'total': 25,
          'list': [
            {'id': 12, 'title': '游戏测试', 'type': 0},
          ],
        },
      );
    final repository = HomeRepository(client);

    final result = await repository.search(
      '游戏',
      type: -1,
      page: 2,
      size: 10,
      field: SearchField.title,
      sort: SearchSort.mostViewed,
    );

    expect(client.requestedPath, '/v1/search/resource');
    expect(client.requestedQuery, {
      'text': '游戏',
      'fields': 'title',
      'type': -1,
      'sort': 'view',
      'page': 2,
      'size': 10,
    });
    expect(result.items.single.id, 12);
    expect(result.total, 25);
    expect(result.hasMore, isTrue);
  });

  test('title-and-content search uses the server default field scope',
      () async {
    final client = _FakeApiClient();
    final repository = HomeRepository(client);

    await repository.search('动画');

    expect(client.requestedQuery, isNot(contains('fields')));
    expect(client.requestedQuery?['sort'], 'all');
    expect(client.requestedQuery?['page'], 1);
    expect(client.requestedQuery?['size'], 20);
  });

  test('user search returns server paging metadata', () async {
    final client = _FakeApiClient()
      ..response = const ApiResponse(
        code: 1,
        message: '成功',
        data: {
          'total': '21',
          'list': [
            {'id': 7, 'name': '游戏玩家'},
          ],
        },
      );
    final repository = HomeRepository(client);

    final result = await repository.searchUserPage(
      '游戏',
      page: 2,
      size: 10,
    );

    expect(client.requestedPath, '/v1/search/user');
    expect(client.requestedQuery, {'user': '游戏', 'page': 2, 'size': 10});
    expect(result.items.single.id, 7);
    expect(result.total, 21);
    expect(result.hasMore, isTrue);
  });
}
