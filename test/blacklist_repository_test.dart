import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/mfuns_api_client.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

class _FakeApiClient extends MfunsApiClient {
  String? postedPath;
  Map<String, Object?>? postedBody;
  var profileRequestCount = 0;

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    if (path == '/v1/blacklist/get') {
      return const ApiResponse(
        code: 1,
        message: '成功',
        data: {
          'list': [
            {
              'id': 2058,
              'user_id': 17627,
              'black_user_id': 74384,
              'black_user_info': {
                'id': 74384,
                'name': '测试用户',
                'avatar': '/static/74384.png',
              },
            },
            123,
          ],
        },
      );
    }
    expect(path, '/v1/user/get_user');
    profileRequestCount++;
    final id = query['id'] as int;
    return ApiResponse(
      code: 1,
      message: '成功',
      data: {
        'id': id,
        'name': id == 74384 ? '测试用户' : '另一个用户',
        'avatar': '/static/$id.png',
      },
    );
  }

  @override
  Future<ApiResponse> postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    postedPath = path;
    postedBody = body;
    return const ApiResponse(code: 1, message: '成功', data: null);
  }
}

void main() {
  test('parses blacklist ids and loads names and avatars for every user',
      () async {
    final client = _FakeApiClient();
    final repository = HomeRepository(client);

    final users = await repository.getBlacklist();

    expect(users.map((user) => user.id), [74384, 123]);
    expect(users.any((user) => user.id == 17627), isFalse);
    expect(users.any((user) => user.id == 2058), isFalse);
    expect(users.first.name, '测试用户');
    expect(users.first.avatar, 'https://cdn2.mfuns.net/static/74384.png');
    expect(users.last.name, '另一个用户');
    expect(users.last.avatar, 'https://cdn2.mfuns.net/static/123.png');
    // 接口自带 black_user_info 的条目不应重复请求用户资料。
    expect(client.profileRequestCount, 1);
  });

  test('checks blocked status using the blacklist endpoint', () async {
    final repository = HomeRepository(_FakeApiClient());

    expect(await repository.isUserBlocked(74384), isTrue);
    expect(await repository.isUserBlocked(17627), isFalse);
    expect(await repository.isUserBlocked(999), isFalse);
    expect(await repository.isUserBlocked(2058), isFalse);
  });

  test('uses add and delete blacklist JSON endpoints', () async {
    final client = _FakeApiClient();
    final repository = HomeRepository(client);

    await repository.setBlocked(userId: 74384, blocked: true);
    expect(client.postedPath, '/v1/blacklist/add');
    expect(client.postedBody, {'user_id': 74384});

    await repository.setBlocked(userId: 74384, blocked: false);
    expect(client.postedPath, '/v1/blacklist/delete');
    expect(client.postedBody, {'user_id': 74384});
  });
}
