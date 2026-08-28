import 'package:flutter/widgets.dart';

/// 全局路由观察器。
///
/// 挂到 [MaterialApp.navigatorObservers] 后，页面组件（如全局播放器）通过
/// [RouteAware] 感知自身路由的可见性变化（`didPushNext` / `didPopNext`），
/// 从而在“播放器生命周期”之外补上“路由可见生命周期”。
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
