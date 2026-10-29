import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/app/mfuns_app.dart';
import 'package:mfuns_flutter/core/config/user_preferences.dart';
import 'package:mfuns_flutter/app/app_controller.dart';
import 'package:mfuns_flutter/core/network/mfuns_api_client.dart';
import 'package:mfuns_flutter/features/auth/auth_repository.dart';
import 'package:mfuns_flutter/features/auth/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _account = StoredAccount(
  accessToken: 'test-token',
  userId: 7,
  displayName: '缓存昵称',
  avatar: '',
  levelId: 3,
  exp: 120,
  nekoCoin: 45.5,
);

class _MemoryStore extends SessionStore {
  List<StoredAccount> saved = [_account];
  String? legacy;
  @override
  Future<List<StoredAccount>> readAccounts() async => saved;
  @override
  Future<void> writeAccounts(List<StoredAccount> accounts) async =>
      saved = accounts;
  @override
  Future<String?> readLegacyToken() async => legacy;
  @override
  Future<void> clearLegacy() async => legacy = null;
}

class _Api extends MfunsApiClient {
  Object? info;
  Completer<ApiResponse>? pending;
  @override
  Future<ApiResponse> get(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    if (path != '/v1/user/info' || info == null) {
      throw const MfunsApiException('网络不可用');
    }
    if (pending != null) return pending!.future;
    return ApiResponse(code: 1, message: '', data: info);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'background_notifications': false});
  });

  test('断网恢复使用缓存资料且不标记账号失效，联网重试更新快照', () async {
    final api = _Api();
    final store = _MemoryStore();
    final controller = AppController(sessionStore: store, apiClient: api);
    // 避免启动通知插件；偏好使用项目公开的保存接口。
    await controller.setBackgroundNotifications(false);
    await controller.initialize();
    expect(controller.session?.displayName, '缓存昵称');
    expect(controller.session?.levelId, 3);
    expect(controller.session?.exp, 120);
    expect(controller.session?.nekoCoin, 45.5);
    expect(controller.isAccountExpired(_account), isFalse);
    expect(controller.sessionSyncError, '网络不可用');
    expect(api.isAuthenticated, isTrue);

    api.info = {
      'login': true,
      'user': {'id': 7, 'name': '新昵称'},
    };
    await controller.refreshSession();
    expect(controller.session?.displayName, '新昵称');
    expect(controller.sessionSyncError, isNull);
    expect(store.saved.single.displayName, '新昵称');
  });

  test('联网校验完成前即可显示本地账号', () async {
    final api = _Api()..info = {};
    api.pending = Completer<ApiResponse>();
    final controller = AppController(
      sessionStore: _MemoryStore(),
      apiClient: api,
    );
    await controller.setBackgroundNotifications(false);
    final initializing = controller.initialize();
    await Future<void>.delayed(Duration.zero);
    expect(controller.session?.userId, 7);
    expect(controller.isRestoringSession, isTrue);
    api.pending!.complete(
      const ApiResponse(
        code: 1,
        message: '',
        data: {
          'login': true,
          'user': {'id': 7, 'name': '在线昵称'},
        },
      ),
    );
    await initializing;
    expect(controller.session?.displayName, '在线昵称');
  });

  test('只有明确的 login false 才标记失效', () async {
    final api = _Api()..info = {'login': false};
    final controller = AppController(
      sessionStore: _MemoryStore(),
      apiClient: api,
    );
    await controller.setBackgroundNotifications(false);
    await controller.initialize();
    expect(controller.session, isNull);
    expect(controller.isAccountExpired(_account), isTrue);
    expect(api.isAuthenticated, isFalse);
  });

  test('响应缺少登录标记时保留缓存，不误报凭证失效', () async {
    final api = _Api()..info = {};
    final controller = AppController(
      sessionStore: _MemoryStore(),
      apiClient: api,
    );
    await controller.setBackgroundNotifications(false);
    await controller.initialize();
    expect(controller.session?.userId, 7);
    expect(controller.isAccountExpired(_account), isFalse);
    expect(controller.sessionSyncError, isNotNull);
  });

  test('离线切换账号与退出回退均保留目标账号缓存', () async {
    final api = _Api();
    final store = _MemoryStore();
    final controller = AppController(sessionStore: store, apiClient: api);
    await controller.setBackgroundNotifications(false);
    await controller.initialize();
    const second = StoredAccount(
      accessToken: 'second-test-token',
      userId: 8,
      displayName: '另一个账号',
      avatar: '',
    );
    expect(await controller.switchToAccount(second), isNull);
    expect(controller.session?.userId, 8);
    expect(controller.isAccountExpired(second), isFalse);
    await controller.logoutCurrent();
    expect(controller.session?.userId, 7);
    await controller.logoutCurrent();
    expect(controller.session, isNull);
    expect(store.saved, isEmpty);
    expect(api.isAuthenticated, isFalse);
  });

  test('刷新时网络失败保留会话，明确失效时退出', () async {
    final api = _Api();
    final controller = AppController(
      sessionStore: _MemoryStore(),
      apiClient: api,
    );
    await controller.setBackgroundNotifications(false);
    await controller.initialize();
    await controller.refreshSession();
    expect(controller.session?.userId, 7);
    expect(api.isAuthenticated, isTrue);
    api.info = {'login': false};
    await controller.refreshSession();
    expect(controller.session, isNull);
    expect(controller.isAccountExpired(_account), isTrue);
    expect(api.isAuthenticated, isFalse);
  });

  test('刷新旧账号的响应不会覆盖已切换的账号或凭证', () async {
    final api = _Api();
    final controller = AppController(
      sessionStore: _MemoryStore(),
      apiClient: api,
    );
    await controller.setBackgroundNotifications(false);
    await controller.initialize();
    api.info = {};
    final pending = Completer<ApiResponse>();
    api.pending = pending;
    final refreshing = controller.refreshSession();
    api.pending = null;
    api.info = null;
    const second = StoredAccount(
      accessToken: 'second-test-token',
      userId: 8,
      displayName: '另一个账号',
      avatar: '',
    );
    await controller.switchToAccount(second);
    pending.complete(
      const ApiResponse(code: 1, message: '', data: {'login': false}),
    );
    await refreshing;
    expect(controller.session?.userId, 8);
    expect(api.isAuthenticated, isTrue);
  });

  testWidgets('离线我的页面显示缓存昵称和重试入口', (tester) async {
    await UserPreferences.saveBackgroundNotifications(false);
    final controller = AppController(
      sessionStore: _MemoryStore(),
      apiClient: _Api(),
    );
    await tester.pumpWidget(MfunsApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('缓存昵称'), findsOneWidget);
    expect(find.text('登录 Mfuns'), findsNothing);
    expect(find.text('暂时无法同步账号信息，正在显示本地缓存'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('旧凭证迁移遇到断网不会删除凭证', () async {
    final store = _MemoryStore()
      ..saved = []
      ..legacy = 'legacy-test-token';
    final controller = AppController(sessionStore: store, apiClient: _Api());
    await controller.setBackgroundNotifications(false);
    await controller.initialize();
    expect(store.legacy, 'legacy-test-token');
  });

  test('restore 网络错误继续上抛，明确未登录返回空', () async {
    final api = _Api();
    final repository = AuthRepository(api);
    await expectLater(
      repository.restore('test-token'),
      throwsA(isA<MfunsApiException>()),
    );
    api.info = {'login': false};
    expect(await repository.restore('test-token'), isNull);
  });
}
