import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../widgets/content_link_handler.dart';

/// 链接唤醒路由：监听 `mfuns://` 协议与 `mfuns.net`（含 www/m 子域）及
/// `mfuns.wgen.top` 域名的深链，在应用内打开对应的视频/文章/动态页面。
class LinkRouter {
  LinkRouter({required this.controller, required this.navigatorKey});

  final AppController controller;
  final GlobalKey<NavigatorState> navigatorKey;

  StreamSubscription<Uri>? _subscription;

  Future<void> start() async {
    try {
      final appLinks = AppLinks();
      final initial = await appLinks.getInitialLink();
      if (initial != null) _route(initial.toString());
      _subscription =
          appLinks.uriLinkStream.listen((uri) => _route(uri.toString()));
    } catch (_) {
      // 平台不支持深链时静默。
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  void _route(String url, {int retries = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        // 首帧尚未就绪时延迟重试，避免初始深链丢失。
        if (retries < 10) {
          Future.delayed(
              const Duration(milliseconds: 200),
              () => _route(url, retries: retries + 1));
        }
        return;
      }
      final target = parseMfunsLink(url);
      if (target == null) return;
      pushMfunsTargetOnNavigator(navigator, controller, target);
    });
  }
}
