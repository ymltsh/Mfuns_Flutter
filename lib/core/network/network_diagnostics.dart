import 'dart:async';
import 'dart:io';

import '../config/app_config.dart';
import 'mfuns_api_client.dart';

/// 单个诊断检查项的结果。
class DiagCheckResult {
  const DiagCheckResult({
    required this.ok,
    required this.message,
    this.latency,
  });

  /// 检查是否通过。
  final bool ok;

  /// 结果详情（含失败原因）。
  final String message;

  /// 本次检查耗时；无耗时的检查项（如静态信息）为 null。
  final Duration? latency;
}

/// 网络类型（按网卡名启发式判断，不依赖平台插件）。
enum NetType { none, wifi, cellular, ethernet, vpn, other }

/// 根据网卡名判断网络类型。优先 Wi-Fi，其次移动网络，再有线与 VPN。
NetType classifyNetType(Iterable<String> names) {
  if (names.isEmpty) return NetType.none;
  String? find(bool Function(String) test) {
    for (final name in names) {
      if (test(name.toLowerCase())) return name;
    }
    return null;
  }

  if (find((n) =>
          n.contains('wlan') ||
          n.contains('wifi') ||
          n.contains('wi-fi')) !=
      null) {
    return NetType.wifi;
  }
  if (find((n) =>
          n.contains('rmnet') ||
          n.contains('cellular') ||
          n.contains('ccmni') ||
          n.contains('cdma') ||
          n.contains('pdp')) !=
      null) {
    return NetType.cellular;
  }
  if (find((n) => n.contains('eth') || n.contains('ethernet')) != null) {
    return NetType.ethernet;
  }
  if (find((n) => n.contains('tun') || n.contains('tap') || n.contains('ppp')) !=
      null) {
    return NetType.vpn;
  }
  return NetType.other;
}

/// 耗时展示：不足 1 秒用毫秒，否则保留一位小数秒。
String formatDuration(Duration duration) {
  if (duration.inMilliseconds < 1000) {
    return '${duration.inMilliseconds} ms';
  }
  return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';
}

/// 网络诊断引擎：纯 dart:io 实现，不引入额外插件。
///
/// 检查项与优先级：
///   P0 网络连接状态 / DNS 解析 / TCP·HTTPS 连接 / 延迟 / 业务 HTTP 请求；
///   P1 IPv4·IPv6 / 多域名探测。
class NetworkDiagnostics {
  NetworkDiagnostics({HttpClient? httpClient})
      : _http = (httpClient ?? HttpClient())
          ..connectionTimeout = const Duration(seconds: 8);

  final HttpClient _http;

  /// 单次网络操作的超时上限。
  static const timeout = Duration(seconds: 10);

  /// 设备信息（纯本地，无网络请求）。
  static String deviceInfoSummary() {
    final os = Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
            ? 'iOS'
            : Platform.isWindows
                ? 'Windows'
                : Platform.isMacOS
                    ? 'macOS'
                    : Platform.isLinux
                        ? 'Linux'
                        : '未知平台';
    return '系统：$os · ${Platform.operatingSystemVersion}';
  }

  /// P0 网络连接状态：Wi-Fi / 移动网络 / 无网络。
  Future<DiagCheckResult> connectionStatus() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
      );
      if (interfaces.isEmpty) {
        return const DiagCheckResult(ok: false, message: '未检测到可用网卡（无网络）');
      }
      final type = classifyNetType(interfaces.map((i) => i.name));
      final label = switch (type) {
        NetType.wifi => 'Wi-Fi',
        NetType.cellular => '移动网络',
        NetType.ethernet => '有线网络',
        NetType.vpn => 'VPN 隧道',
        NetType.other => '其他网络',
        NetType.none => '无网络',
      };
      final names = interfaces
          .map((i) =>
              '${i.name}（${i.addresses.map((a) => a.address).join('/')}）')
          .join('、');
      return DiagCheckResult(
        ok: type != NetType.none,
        message: '$label · $names',
      );
    } on Exception catch (error) {
      return DiagCheckResult(ok: false, message: '无法读取网络状态：$error');
    }
  }

  /// P0 DNS 解析：判断域名解析是否正常。
  Future<DiagCheckResult> dnsResolve(String host) async {
    final watch = Stopwatch()..start();
    try {
      final addresses = await InternetAddress.lookup(host).timeout(timeout);
      watch.stop();
      if (addresses.isEmpty) {
        return DiagCheckResult(
          ok: false,
          message: '$host 未解析到任何地址',
          latency: watch.elapsed,
        );
      }
      final ipv4 = addresses
          .where((a) => a.type == InternetAddressType.IPv4)
          .length;
      final ipv6 = addresses
          .where((a) => a.type == InternetAddressType.IPv6)
          .length;
      final samples = addresses.take(3).map((a) => a.address).join('、');
      final suffix = addresses.length > 3 ? ' 等 ${addresses.length} 个' : '';
      return DiagCheckResult(
        ok: true,
        message: '$host 解析正常：IPv4×$ipv4、IPv6×$ipv6（$samples$suffix）',
        latency: watch.elapsed,
      );
    } on TimeoutException {
      return DiagCheckResult(ok: false, message: '$host DNS 解析超时');
    } on SocketException catch (error) {
      return DiagCheckResult(
        ok: false,
        message: '$host DNS 解析失败：${error.message}',
      );
    }
  }

  /// P0 TCP 连接：判断目标主机端口是否可达。
  Future<DiagCheckResult> tcpConnect(String host, int port) async {
    final watch = Stopwatch()..start();
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      watch.stop();
      await socket.close();
      return DiagCheckResult(
        ok: true,
        message: '已连通 $host:$port',
        latency: watch.elapsed,
      );
    } on SocketException catch (error) {
      return DiagCheckResult(
        ok: false,
        message: '$host:$port 连接失败：${error.message}',
        latency: watch.elapsed,
      );
    } on TimeoutException {
      return DiagCheckResult(
        ok: false,
        message: '$host:$port 连接超时',
        latency: watch.elapsed,
      );
    }
  }

  /// P0 HTTPS 探测：完整 TLS 握手 + HTTP 请求。
  Future<DiagCheckResult> httpsProbe(String url) async {
    final watch = Stopwatch()..start();
    try {
      final request = await _http.getUrl(Uri.parse(url)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      watch.stop();
      await response.drain<void>();
      return DiagCheckResult(
        ok: true,
        message: '$url → HTTP ${response.statusCode}',
        latency: watch.elapsed,
      );
    } on Exception catch (error) {
      return DiagCheckResult(
        ok: false,
        message: '$url 请求失败：$error',
        latency: watch.elapsed,
      );
    }
  }

  /// P0 延迟：连续多次 TCP 连接耗时取平均，判断网络是否明显卡顿。
  Future<DiagCheckResult> measureLatency({int samples = 3}) async {
    final times = <Duration>[];
    for (var i = 0; i < samples; i++) {
      final result = await tcpConnect(AppConfig.apiHost, 443);
      if (!result.ok || result.latency == null) return result;
      times.add(result.latency!);
    }
    final totalMs = times.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    final average = Duration(milliseconds: totalMs ~/ times.length);
    final per = times.map((d) => '${d.inMilliseconds}ms').join(' / ');
    return DiagCheckResult(
      ok: true,
      message: '$samples 次连接平均 ${average.inMilliseconds} ms（$per）',
      latency: average,
    );
  }

  /// P0 业务 HTTP 请求：走与 App 相同的 MfunsApiClient 代码路径，
  /// 判断「能上网」还是「能访问目标服务」。
  Future<DiagCheckResult> businessApiCheck() async {
    final watch = Stopwatch()..start();
    try {
      final client = MfunsApiClient();
      final response = await client.get('/v1/category/all').timeout(timeout);
      watch.stop();
      return DiagCheckResult(
        ok: response.code == 1,
        message: response.code == 1
            ? '业务接口 /v1/category/all 正常（code=1）'
            : '业务接口返回异常：${response.message}',
        latency: watch.elapsed,
      );
    } on MfunsApiException catch (error) {
      return DiagCheckResult(
        ok: false,
        message: '业务接口不可用：${error.message}',
        latency: watch.elapsed,
      );
    } on TimeoutException {
      return DiagCheckResult(
        ok: false,
        message: '业务接口请求超时',
        latency: watch.elapsed,
      );
    }
  }

  /// P1 IPv4 / IPv6：分别解析并建立 TCP 连接，判断是否存在单栈异常。
  Future<DiagCheckResult> ipStackCheck(String host) async {
    final v4 = await _probeStack(host, InternetAddressType.IPv4);
    final v6 = await _probeStack(host, InternetAddressType.IPv6);
    final lines = <String>[
      v4 == null ? 'IPv4 ✗' : 'IPv4 ✓ $v4',
      v6 == null ? 'IPv6 ✗' : 'IPv6 ✓ $v6',
    ];
    final ok = v4 != null || v6 != null;
    final singleStackIssue = (v4 == null) != (v6 == null);
    return DiagCheckResult(
      ok: ok,
      message: ok
          ? '${lines.join('，')}${singleStackIssue ? '，存在单栈异常' : ''}'
          : '${lines.join('，')}，双栈均不可达',
    );
  }

  Future<String?> _probeStack(String host, InternetAddressType type) async {
    try {
      final addresses =
          await InternetAddress.lookup(host, type: type).timeout(timeout);
      if (addresses.isEmpty) return null;
      final socket =
          await Socket.connect(addresses.first.address, 443, timeout: timeout);
      await socket.close();
      return addresses.first.address;
    } on Exception {
      return null;
    }
  }

  /// P1 多域名探测：排除单个 CDN / 域名故障。
  Future<DiagCheckResult> multiDomainProbe() async {
    final urls = <String>[
      'https://${AppConfig.apiHost}/',
      'https://${AppConfig.latestMfunsHost}/',
      'https://cdn2.mfuns.net/',
      'https://vod.mfuns.net/',
    ];
    final lines = <String>[];
    var allOk = true;
    for (final url in urls) {
      final result = await httpsProbe(url);
      allOk = allOk && result.ok;
      final latency =
          result.latency == null ? '' : ' · ${formatDuration(result.latency!)}';
      lines.add('${result.ok ? '✓' : '✗'} $url${result.ok ? latency : ''}');
    }
    return DiagCheckResult(ok: allOk, message: lines.join('\n'));
  }
}
