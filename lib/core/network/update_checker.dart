import 'dart:convert';
import 'dart:io';

import '../config/app_config.dart';

/// 单个版本信息（`version.json` 的 latest / history 条目）。
class UpdateRelease {
  const UpdateRelease({
    required this.version,
    this.build,
    this.name = '',
    this.date = '',
    this.notes = '',
    this.androidUrl = '',
    this.windowsUrl = '',
    this.page = '',
  });

  final String version;
  final int? build;
  final String name;
  final String date;
  final String notes;
  final String androidUrl;
  final String windowsUrl;
  final String page;

  factory UpdateRelease.fromJson(Map<String, dynamic> json) {
    final urls = json['urls'];
    return UpdateRelease(
      version: '${json['version'] ?? ''}',
      build: _asInt(json['build']),
      name: '${json['name'] ?? ''}',
      date: '${json['date'] ?? ''}',
      notes: '${json['notes'] ?? ''}',
      androidUrl: urls is Map<String, dynamic>
          ? '${urls['android'] ?? ''}'
          : '',
      windowsUrl: urls is Map<String, dynamic>
          ? '${urls['windows'] ?? ''}'
          : '',
      page: '${json['page'] ?? ''}',
    );
  }

  static int? _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');
}

/// 更新清单：最新版本 + 历史版本列表。
class UpdateManifest {
  const UpdateManifest({required this.latest, required this.history});

  final UpdateRelease? latest;
  final List<UpdateRelease> history;

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    final rawLatest = json['latest'];
    final rawHistory = json['history'];
    return UpdateManifest(
      latest: rawLatest is Map<String, dynamic>
          ? UpdateRelease.fromJson(rawLatest)
          : null,
      history: rawHistory is List
          ? rawHistory
              .whereType<Map<String, dynamic>>()
              .map(UpdateRelease.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}

class UpdateChecker {
  const UpdateChecker._();

  /// 版本号形如 "1.0.5"；候选版本大于当前版本（含 build 号）时为有新版本。
  static bool isNewer(
    String candidate,
    int? candidateBuild,
    String current,
    int? currentBuild,
  ) {
    final candidateParts = _versionParts(candidate);
    final currentParts = _versionParts(current);
    for (var i = 0; i < 3; i++) {
      if (candidateParts[i] != currentParts[i]) {
        return candidateParts[i] > currentParts[i];
      }
    }
    return (candidateBuild ?? 0) > (currentBuild ?? 0);
  }

  static List<int> _versionParts(String version) {
    final parts = <int>[];
    for (final part in version.split('.')) {
      final value = int.tryParse(part.trim());
      if (value == null) break;
      parts.add(value);
    }
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts;
  }

  /// 从加速站读取仓库内的更新清单（version.json）。
  ///
  /// [acceleratorBase] 为用户自定义加速地址；空值或异常时回退默认加速站。
  static Future<UpdateManifest> fetch({String? acceleratorBase}) async {
    final base = _normalizeBase(acceleratorBase ?? '');
    final url = '$base${AppConfig.updateManifestRawUrl}';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != 200) {
        throw HttpException('更新服务器返回 ${response.statusCode}');
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('更新清单格式不正确');
      }
      return UpdateManifest.fromJson(decoded);
    } finally {
      client.close(force: true);
    }
  }

  /// 规范化加速地址：去空格、补全 http(s):// 前缀与结尾斜杠。
  static String normalizeBase(String value) {
    var base = value.trim();
    if (base.isEmpty) return AppConfig.defaultAcceleratorBase;
    if (!base.startsWith('http://') && !base.startsWith('https://')) {
      base = 'https://$base';
    }
    if (!base.endsWith('/')) base = '$base/';
    return base;
  }

  static String _normalizeBase(String value) =>
      normalizeBase(value.isEmpty ? AppConfig.defaultAcceleratorBase : value);

  /// 拼接加速后的完整地址（用于下载链接等任意 GitHub 地址）。
  static String accelerate(String acceleratorBase, String url) =>
      '${normalizeBase(acceleratorBase)}$url';
}
