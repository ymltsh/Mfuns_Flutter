import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/mfuns_api_client.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

class _FollowApiClient extends MfunsApiClient {
  _FollowApiClient(this.status);

  final Object? status;
  var requestCount = 0;

  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    expect(path, '/v1/follow/status');
    expect(query, {'user_id': 12});
    requestCount++;
    return ApiResponse(code: 1, message: '成功', data: {'status': status});
  }
}

void main() {
  test('maps follow relations to user-facing labels', () {
    expect(followRelationLabel(FollowRelation.none), '关注');
    expect(followRelationLabel(FollowRelation.following), '已关注');
    expect(followRelationLabel(FollowRelation.mutual), '已互关');
  });

  for (final (status, expected) in <(Object?, FollowRelation)>[
    (0, FollowRelation.none),
    (1, FollowRelation.following),
    (2, FollowRelation.mutual),
    ('2', FollowRelation.mutual),
    (true, FollowRelation.following),
  ]) {
    test('parses follow status $status as $expected', () async {
      final client = _FollowApiClient(status);
      final repository = HomeRepository(client);

      expect(await repository.getFollowRelation(12), expected);
      expect(client.requestCount, 1);
    });
  }

  test('mutual status is also considered following', () async {
    final repository = HomeRepository(_FollowApiClient(2));

    expect(await repository.followStatus(12), isTrue);
  });
}
