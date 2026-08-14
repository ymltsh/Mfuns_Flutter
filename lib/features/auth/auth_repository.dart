import '../../core/network/mfuns_api_client.dart';

class UserSession {
  const UserSession({
    required this.accessToken,
    required this.userId,
    required this.displayName,
    required this.avatar,
    this.levelId,
    this.exp,
  });

  final String accessToken;
  final int? userId;
  final String displayName;
  final String avatar;

  /// 等级 ID（1-10，对应 D/D+/…/S+），登录用户 `/v1/user/info` 返回。
  final int? levelId;

  /// 当前经验值。
  final int? exp;
}

class AuthRepository {
  const AuthRepository(this._client);

  final MfunsApiClient _client;

  Future<UserSession> login({
    required String account,
    required String password,
  }) async {
    final login = await _client.postForm('/v1/auth/login', {
      'account': account,
      'password': password,
    });
    final loginData = _asMap(login.data);
    final token = loginData['access_token']?.toString() ?? '';
    if (token.isEmpty) {
      throw const MfunsApiException('登录响应中没有 access_token');
    }

    _client.setAccessToken(token);
    try {
      final userInfo = await _client.get('/v1/user/info');
      return _sessionFromUserInfo(token, userInfo.data);
    } catch (_) {
      _client.clearAccessToken();
      rethrow;
    }
  }

  Future<bool> validateCurrentToken() async {
    if (!_client.isAuthenticated) return false;
    try {
      final result = await _client.get('/v1/user/info');
      return _asMap(result.data)['login'] == true;
    } on MfunsApiException {
      return false;
    }
  }

  Future<UserSession?> restore(String token) async {
    _client.setAccessToken(token);
    try {
      final userInfo = await _client.get('/v1/user/info');
      return _sessionFromUserInfo(token, userInfo.data);
    } on MfunsApiException {
      _client.clearAccessToken();
      return null;
    }
  }

  UserSession _sessionFromUserInfo(String token, Object? data) {
    final info = _asMap(data);
    if (info['login'] != true) {
      throw const MfunsApiException('登录状态校验失败');
    }
    final user = _asMap(info['user'] ?? info['user_info'] ?? info);
    return UserSession(
      accessToken: token,
      userId: _asInt(user['id'] ?? user['user_id']),
      displayName: '${user['name'] ?? user['username'] ?? '已登录用户'}',
      avatar: _avatarUrl(user['avatar'] ?? user['user_avatar']),
      levelId: _asInt(user['level_id'] ?? user['level_badge']),
      exp: _asInt(user['exp']),
    );
  }

  String _avatarUrl(Object? value) {
    final avatar = '${value ?? ''}'.trim();
    if (avatar.isEmpty) return '';
    if (avatar.startsWith('//')) return 'https:$avatar';
    if (avatar.startsWith('/')) return 'https://cdn2.mfuns.net$avatar';
    if (avatar.startsWith('static/')) return 'https://cdn2.mfuns.net/$avatar';
    return avatar;
  }

  Map<String, dynamic> _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : const {};

  int? _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');
}
