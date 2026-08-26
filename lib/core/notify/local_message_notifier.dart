import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 消息前台通知（Notification API）：新私信/赞/评论/提及到达时
/// 按类型弹出系统通知；点击通知通过 [init] 传入的 onTap 跳转对应页面。
/// 平台不支持或权限未授予时静默，不影响消息功能本身。
class LocalMessageNotifier {
  LocalMessageNotifier._();

  static final LocalMessageNotifier instance = LocalMessageNotifier._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  var _initialized = false;
  var _permissionRequested = false;

  static const _channelId = 'com.ygen.mfuns_flutter.messages';

  /// 私信 / 赞 / 评论 / 提及 / 系统通知的 payload 与通知 id（相互独立）。
  static const payloadDm = 'dm';
  static const payloadLike = 'like';
  static const payloadComment = 'comment';
  static const payloadMention = 'mention';
  static const payloadSystem = 'system';

  /// 初始化通知通道并请求 Android 13+ 的通知权限（可重复调用）。
  /// [onTap] 在用户点击通知时回调，参数为对应 payload（用于跳转页面）。
  Future<void> init({void Function(String payload)? onTap}) async {
    if (_initialized || kIsWeb) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) onTap?.call(payload);
        },
      );
      _initialized = true;
      // 冷启动：App 由点击通知拉起时同样触发跳转。
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        onTap?.call(payload);
      }
    } catch (_) {
      // 初始化失败不影响消息功能。
    }
  }

  /// 请求 Android 13+ 运行时通知权限；已授予或已拒绝过则直接返回。
  Future<void> requestPermission() async {
    if (_permissionRequested || kIsWeb) return;
    _permissionRequested = true;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> showDm(int count) => _show(
        id: 1001,
        title: '新私信',
        body: count <= 1 ? '你收到 1 条新私信' : '你收到 $count 条新私信',
        payload: payloadDm,
      );

  Future<void> showLikes(int count) => _show(
        id: 1002,
        title: '收到赞',
        body: count <= 1 ? '有 1 个人赞了你的内容' : '有 $count 个人赞了你的内容',
        payload: payloadLike,
      );

  Future<void> showComments(int count) => _show(
        id: 1003,
        title: '收到评论',
        body: count <= 1 ? '你收到 1 条新评论' : '你收到 $count 条新评论',
        payload: payloadComment,
      );

  Future<void> showMentions(int count) => _show(
        id: 1004,
        title: '@提及',
        body: count <= 1 ? '有人 @ 了你' : '有 $count 个人 @ 了你',
        payload: payloadMention,
      );

  Future<void> showSystem(int count) => _show(
        id: 1005,
        title: '系统通知',
        body: count <= 1 ? '你收到 1 条新系统通知' : '你收到 $count 条新系统通知',
        payload: payloadSystem,
      );

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!_initialized || kIsWeb) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            '私信与通知',
            channelDescription: '收到新私信、赞、评论或 @提及时提醒',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (_) {}
  }
}
