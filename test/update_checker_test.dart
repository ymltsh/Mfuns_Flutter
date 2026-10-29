import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/update_checker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('按系统 ABI 优先级匹配，兼容 32 位系统与 x86_64', () {
    final release = UpdateRelease.fromJson({
      'version': '1.6.8',
      'build': '64',
      'urls': {
        'android': 'https://example.test/releases',
        'android_abis': {
          'armeabi-v7a': 'https://example.test/arm.apk',
          'arm64-v8a': 'https://example.test/arm64.apk',
          'x86_64': 'https://example.test/x64.apk',
        },
      },
    });
    expect(release.build, 64);
    expect(
      release.androidDownloadUrl(['arm64-v8a', 'armeabi-v7a']),
      'https://example.test/arm64.apk',
    );
    expect(
      release.androidDownloadUrl(['armeabi-v7a']),
      'https://example.test/arm.apk',
    );
    expect(
      release.androidDownloadUrl(['x86_64', 'arm64-v8a']),
      'https://example.test/x64.apk',
    );
    expect(release.androidDownloadUrl(['riscv64']), isNull);
    expect(release.androidDownloadUrl([]), isNull);
  });

  test('旧清单仍可下载通用包，忽略无效架构字段', () {
    final release = UpdateRelease.fromJson({
      'version': '1.6.7',
      'urls': {
        'android': 'https://example.test/universal.apk',
        'android_abis': {'arm64-v8a': null, 'x86_64': 123, 'armeabi-v7a': '  '},
      },
    });
    expect(release.androidAbiUrls, isEmpty);
    expect(
      release.androidDownloadUrl([]),
      'https://example.test/universal.apk',
    );
    expect(
      UpdateRelease.fromJson({
        'version': '1',
        'urls': {'android_abis': 'invalid'},
      }).androidDownloadUrl([]),
      isNull,
    );
  });

  test('没有首选 ABI 包时选择系统支持的下一种，绝不选不兼容架构', () {
    const release = UpdateRelease(
      version: '2',
      androidAbiUrls: {'armeabi-v7a': 'arm.apk'},
    );
    expect(release.androidDownloadUrl(['arm64-v8a', 'armeabi-v7a']), 'arm.apk');
    expect(release.androidDownloadUrl(['x86_64']), isNull);
  });

  test('原生通道返回真实系统支持的架构，失败时交由 UI 提供手动选择', () async {
    const channel = MethodChannel('mfuns/device');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'supportedAbis');
      return ['arm64-v8a', 'armeabi-v7a'];
    });
    expect(await UpdateChecker.androidSupportedAbis(), [
      'arm64-v8a',
      'armeabi-v7a',
    ]);
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'unavailable'),
    );
    expect(await UpdateChecker.androidSupportedAbis(), isEmpty);
    messenger.setMockMethodCallHandler(channel, null);
    expect(await UpdateChecker.androidSupportedAbis(), isEmpty);
  });

  test('parses the manifest with latest and history fields', () {
    final manifest = UpdateManifest.fromJson({
      'latest': {
        'version': '1.0.6',
        'build': 6,
        'name': 'Mfuns Flutter v1.0.6',
        'date': '2026-08-20',
        'notes': '新功能',
        'urls': {
          'android': 'https://example.test/app.apk',
          'windows': 'https://example.test/app.zip',
        },
        'page': 'https://example.test/releases/v1.0.6',
      },
      'history': [
        {'version': '1.0.5', 'build': 5, 'name': 'v1.0.5', 'notes': '旧版本'},
      ],
    });

    expect(manifest.latest, isNotNull);
    expect(manifest.latest!.version, '1.0.6');
    expect(manifest.latest!.build, 6);
    expect(manifest.latest!.androidUrl, 'https://example.test/app.apk');
    expect(manifest.latest!.windowsUrl, 'https://example.test/app.zip');
    expect(manifest.latest!.page, 'https://example.test/releases/v1.0.6');
    expect(manifest.history, hasLength(1));
    expect(manifest.history.first.version, '1.0.5');
  });

  test('tolerates missing fields', () {
    final manifest = UpdateManifest.fromJson({
      'latest': {'version': '1.1.0'},
    });
    expect(manifest.latest!.version, '1.1.0');
    expect(manifest.latest!.build, isNull);
    expect(manifest.latest!.androidUrl, '');
    expect(manifest.history, isEmpty);
  });

  test('isNewer compares version parts and build numbers', () {
    expect(UpdateChecker.isNewer('1.0.6', 6, '1.0.5', 5), isTrue);
    expect(UpdateChecker.isNewer('1.1.0', 0, '1.0.9', 99), isTrue);
    expect(UpdateChecker.isNewer('2.0.0', 0, '1.9.9', 99), isTrue);
    expect(UpdateChecker.isNewer('1.0.5', 5, '1.0.5', 5), isFalse);
    expect(UpdateChecker.isNewer('1.0.5', 4, '1.0.5', 5), isFalse);
    expect(UpdateChecker.isNewer('1.0.4', 99, '1.0.5', 5), isFalse);
    expect(UpdateChecker.isNewer('1.0.5', 6, '1.0.5', 5), isTrue);
  });

  test('isNewer handles malformed versions gracefully', () {
    expect(UpdateChecker.isNewer('', 0, '1.0.5', 5), isFalse);
    expect(UpdateChecker.isNewer('abc', 0, '1.0.5', 5), isFalse);
  });

  test('normalizeBase fills scheme and trailing slash', () {
    expect(
      UpdateChecker.normalizeBase('hub.wgen.top'),
      'https://hub.wgen.top/',
    );
    expect(
      UpdateChecker.normalizeBase('https://acc.example.com'),
      'https://acc.example.com/',
    );
    expect(UpdateChecker.normalizeBase(' https://a.com/ '), 'https://a.com/');
    expect(UpdateChecker.normalizeBase(''), 'https://hub.wgen.top/');
  });

  test('accelerate prefixes any GitHub url with the base', () {
    expect(
      UpdateChecker.accelerate(
        'hub.wgen.top',
        'https://github.com/ymltsh/Mfuns_Flutter/releases/'
            'download/v1.0.8/mfuns-flutter-1.0.8.apk',
      ),
      'https://hub.wgen.top/https://github.com/ymltsh/Mfuns_Flutter/'
      'releases/download/v1.0.8/mfuns-flutter-1.0.8.apk',
    );
  });
}
