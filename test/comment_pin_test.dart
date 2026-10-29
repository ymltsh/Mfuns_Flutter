import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/mfuns_api_client.dart';
import 'package:mfuns_flutter/features/home/home_repository.dart';

class _FakeApiClient extends MfunsApiClient {
  String? postedPath;
  Map<String, Object?>? postedBody;

  @override
  Future<ApiResponse> postJson(String path, Map<String, Object?> body) async {
    postedPath = path;
    postedBody = body;
    return const ApiResponse(code: 1, message: '成功', data: null);
  }
}

void main() {
  test('pins and unpins a comment with the pin endpoint', () async {
    final client = _FakeApiClient();
    final repository = HomeRepository(client);

    await repository.pinComment(42);
    expect(client.postedPath, '/v1/comment/pin');
    expect(client.postedBody, {'id': 42});

    await repository.pinComment(42, cancel: true);
    expect(client.postedPath, '/v1/comment/pin');
    expect(client.postedBody, {'id': 42, 'cancel': 1});
  });
}
