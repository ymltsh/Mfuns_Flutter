import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 当前网络类型（下载策略判断用）。
enum DownloadNetworkType {
  wifi,
  mobile,
  ethernet,
  other,
  unknown;

  bool get isMobile => this == DownloadNetworkType.mobile;

  String get label => switch (this) {
        DownloadNetworkType.wifi => 'Wi-Fi',
        DownloadNetworkType.mobile => '移动网络',
        DownloadNetworkType.ethernet => '有线网络',
        DownloadNetworkType.other => '其他网络',
        DownloadNetworkType.unknown => '未知网络',
      };
}

/// 网络环境探测抽象：生产实现基于 connectivity_plus，测试注入替身。
abstract class DownloadEnvironment {
  Future<DownloadNetworkType> currentNetwork();

  /// 网络类型变化流；无变化事件时返回 null（测试注入）。
  Stream<DownloadNetworkType>? get networkChanges;
}

/// 生产实现：connectivity_plus。
class ConnectivityDownloadEnvironment implements DownloadEnvironment {
  ConnectivityDownloadEnvironment({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<DownloadNetworkType> currentNetwork() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _toType(results.isNotEmpty ? results.first : ConnectivityResult.none);
    } catch (_) {
      // 插件不可用（桌面/测试环境）时视为未知网络，不阻断下载。
      return DownloadNetworkType.unknown;
    }
  }

  @override
  Stream<DownloadNetworkType> get networkChanges {
    try {
      return _connectivity.onConnectivityChanged.map(
          (results) => _toType(results.isNotEmpty ? results.first : ConnectivityResult.none));
    } catch (_) {
      return const Stream.empty();
    }
  }

  DownloadNetworkType _toType(ConnectivityResult result) =>
      switch (result) {
        ConnectivityResult.wifi => DownloadNetworkType.wifi,
        ConnectivityResult.mobile ||
        ConnectivityResult.vpn =>
          DownloadNetworkType.mobile,
        ConnectivityResult.ethernet => DownloadNetworkType.ethernet,
        ConnectivityResult.bluetooth ||
        ConnectivityResult.other ||
        ConnectivityResult.satellite =>
          DownloadNetworkType.other,
        ConnectivityResult.none => DownloadNetworkType.unknown,
      };
}

/// 下载策略：网络限制与并发数。
class DownloadPolicy {
  const DownloadPolicy({
    required this.wifiOnly,
    required this.maxConcurrent,
  });

  static const defaults = DownloadPolicy(
    wifiOnly: true,
    maxConcurrent: 2,
  );

  /// 仅 Wi-Fi 下载：移动网络下新任务被阻止、进行中任务自动暂停。
  final bool wifiOnly;

  /// 最大并发下载数。
  final int maxConcurrent;

  DownloadPolicy copyWith({bool? wifiOnly, int? maxConcurrent}) =>
      DownloadPolicy(
        wifiOnly: wifiOnly ?? this.wifiOnly,
        maxConcurrent: maxConcurrent ?? this.maxConcurrent,
      );

  @override
  bool operator ==(Object other) =>
      other is DownloadPolicy &&
      other.wifiOnly == wifiOnly &&
      other.maxConcurrent == maxConcurrent;

  @override
  int get hashCode => Object.hash(wifiOnly, maxConcurrent);
}

/// 下载策略的本地持久化（shared_preferences）。
class DownloadPreferences {
  static const _keyWifiOnly = 'pref.download_wifi_only';
  static const _keyMaxConcurrent = 'pref.download_max_concurrent';

  static Future<DownloadPolicy> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wifiOnly = prefs.getBool(_keyWifiOnly) ??
          DownloadPolicy.defaults.wifiOnly;
      final maxConcurrent = (prefs.getInt(_keyMaxConcurrent) ??
              DownloadPolicy.defaults.maxConcurrent)
          .clamp(1, 5);
      return DownloadPolicy(
        wifiOnly: wifiOnly,
        maxConcurrent: maxConcurrent,
      );
    } catch (_) {
      return DownloadPolicy.defaults;
    }
  }

  static Future<void> save(DownloadPolicy policy) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyWifiOnly, policy.wifiOnly);
      await prefs.setInt(_keyMaxConcurrent, policy.maxConcurrent);
    } catch (_) {
      // 偏好保存失败不影响下载主流程。
    }
  }
}
