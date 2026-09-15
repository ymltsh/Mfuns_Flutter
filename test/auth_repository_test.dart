import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/mfuns_api_client.dart';
import 'package:mfuns_flutter/features/auth/auth_repository.dart';

class _FakeApiClient extends MfunsApiClient {
  String? postedPath;
  Map<String, Object?>? postedBody;
  String? token;

  @override
  Future<ApiResponse> postJson(String path, Map<String, Object?> body) async {
    postedPath = path;
    postedBody = body;
    if (path == '/v1/auth/send_login_code') {
      return const ApiResponse(code: 1, message: '发送成功', data: null);
    }
    return const ApiResponse(
      code: 1,
      message: '登录成功',
      data: {'access_token': 'sms-token'},
    );
  }

  @override
  void setAccessToken(String value) => token = value;

  @override
  void clearAccessToken() => token = null;

  @override
  Future<ApiResponse> get(String path,
      {Map<String, Object?> query = const {}}) async {
    expect(path, '/v1/user/info');
    return const ApiResponse(
      code: 1,
      message: '成功',
      data: {
        'login': true,
        'user': {'id': 17627, 'name': '验证码用户'},
      },
    );
  }
}

void main() {
  test('sendLoginCode posts the phone as JSON', () async {
    final client = _FakeApiClient();
    final repository = AuthRepository(client);

    final message = await repository.sendLoginCode(phone: '13800138000');

    expect(message, '发送成功');
    expect(client.postedPath, '/v1/auth/send_login_code');
    expect(client.postedBody, {'phone': '13800138000'});
  });

  test('loginBySms posts numeric code and creates a verified session',
      () async {
    final client = _FakeApiClient();
    final repository = AuthRepository(client);

    final session = await repository.loginBySms(
      phone: '13800138000',
      code: '123456',
    );

    expect(client.postedPath, '/v1/auth/login_by_sms');
    expect(client.postedBody, {'phone': '13800138000', 'code': 123456});
    expect(client.token, 'sms-token');
    expect(session.accessToken, 'sms-token');
    expect(session.userId, 17627);
    expect(session.displayName, '验证码用户');
  });
}
