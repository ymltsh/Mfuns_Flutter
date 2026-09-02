import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_repository.dart';

/// 本机保存的一个登录账号（含登录凭证与最近一次同步的用户信息快照）。
/// 应用支持同时保存多个账号，可随时一键切换或删除。
class StoredAccount {
  const StoredAccount({
    required this.accessToken,
    required this.displayName,
    required this.avatar,
    this.userId,
    this.levelId,
    this.exp,
    this.nekoCoin,
    this.lastUsedAt,
  });

  final String accessToken;

  /// 登录用户 UID；服务端信息缺失时为 null。
  final int? userId;

  /// 最近一次会话同步时的昵称/头像快照，用于离线展示。
  final String displayName;
  final String avatar;
  final int? levelId;
  final int? exp;
  final double? nekoCoin;

  /// 最近一次登录/切换时间，用于排序与登录失效后的自动回退。
  final DateTime? lastUsedAt;

  /// 账号在本地存储中的唯一标识：优先 UID，缺失时回退为 token 指纹。
  String get key => keyFor(userId, accessToken);

  static String keyFor(int? userId, String accessToken) {
    if (userId != null) return 'u$userId';
    return 't${accessToken.hashCode}';
  }

  StoredAccount copyWith({
    String? accessToken,
    int? Function()? userId,
    String? displayName,
    String? avatar,
    int? Function()? levelId,
    int? Function()? exp,
    double? Function()? nekoCoin,
    DateTime? lastUsedAt,
    bool clearLastUsedAt = false,
  }) =>
      StoredAccount(
        accessToken: accessToken ?? this.accessToken,
        userId: userId != null ? userId() : this.userId,
        displayName: displayName ?? this.displayName,
        avatar: avatar ?? this.avatar,
        levelId: levelId != null ? levelId() : this.levelId,
        exp: exp != null ? exp() : this.exp,
        nekoCoin: nekoCoin != null ? nekoCoin() : this.nekoCoin,
        lastUsedAt: clearLastUsedAt ? null : (lastUsedAt ?? this.lastUsedAt),
      );

  /// 用登录后的会话创建存储快照；[lastUsedAt] 缺省时取当前时间。
  factory StoredAccount.fromSession(UserSession session,
          {DateTime? lastUsedAt}) =>
      StoredAccount(
        accessToken: session.accessToken,
        userId: session.userId,
        displayName: session.displayName,
        avatar: session.avatar,
        levelId: session.levelId,
        exp: session.exp,
        nekoCoin: session.nekoCoin,
        lastUsedAt: lastUsedAt ?? DateTime.now(),
      );

  Map<String, Object?> toJson() => {
        'access_token': accessToken,
        if (userId != null) 'user_id': userId,
        'name': displayName,
        'avatar': avatar,
        if (levelId != null) 'level_id': levelId,
        if (exp != null) 'exp': exp,
        if (nekoCoin != null) 'neko_coin': nekoCoin,
        if (lastUsedAt != null)
          'last_used_at': lastUsedAt!.millisecondsSinceEpoch,
      };

  static StoredAccount fromJson(Map<String, dynamic> json) {
    final rawLastUsed = json['last_used_at'];
    return StoredAccount(
      accessToken: '${json['access_token'] ?? ''}',
      userId: json['user_id'] is num
          ? (json['user_id'] as num).toInt()
          : int.tryParse('${json['user_id']}'),
      displayName: '${json['name'] ?? '已登录用户'}',
      avatar: '${json['avatar'] ?? ''}',
      levelId: json['level_id'] is num
          ? (json['level_id'] as num).toInt()
          : int.tryParse('${json['level_id']}'),
      exp: json['exp'] is num
          ? (json['exp'] as num).toInt()
          : int.tryParse('${json['exp']}'),
      nekoCoin: json['neko_coin'] is num
          ? (json['neko_coin'] as num).toDouble()
          : double.tryParse('${json['neko_coin']}'),
      lastUsedAt: rawLastUsed is num
          ? DateTime.fromMillisecondsSinceEpoch(rawLastUsed.toInt())
          : null,
    );
  }
}

/// 多账号会话持久化：把「已保存的账号列表 + 每个账号的登录凭证」整体
/// 存入安全存储；旧的单账号 token 在首次读取时迁移为账号列表。
class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accountsKey = 'mfuns.community.saved_accounts.v1';

  /// 旧版本单账号存储 key，仅用于一次性迁移。
  static const _legacyTokenKey = 'mfuns.community.access_token';

  final FlutterSecureStorage _storage;

  Future<List<StoredAccount>> readAccounts() async {
    final raw = await _storage.read(key: _accountsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final accounts = <StoredAccount>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          accounts.add(StoredAccount.fromJson(item));
        }
      }
      return accounts;
    } on FormatException {
      return const [];
    }
  }

  Future<void> writeAccounts(List<StoredAccount> accounts) => _storage.write(
      key: _accountsKey,
      value: jsonEncode(
          accounts.map((account) => account.toJson()).toList(growable: false)));

  Future<String?> readLegacyToken() => _storage.read(key: _legacyTokenKey);

  Future<void> clearLegacy() => _storage.delete(key: _legacyTokenKey);

  Future<void> clear() async {
    await _storage.delete(key: _accountsKey);
    await _storage.delete(key: _legacyTokenKey);
  }
}
