import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/update_checker.dart';

void main() {
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
    expect(UpdateChecker.normalizeBase('hub.wgen.top'),
        'https://hub.wgen.top/');
    expect(UpdateChecker.normalizeBase('https://acc.example.com'),
        'https://acc.example.com/');
    expect(UpdateChecker.normalizeBase(' https://a.com/ '), 'https://a.com/');
    expect(UpdateChecker.normalizeBase(''),
        'https://hub.wgen.top/');
  });

  test('accelerate prefixes any GitHub url with the base', () {
    expect(
      UpdateChecker.accelerate(
          'hub.wgen.top',
          'https://github.com/ymltsh/Mfuns_Flutter/releases/'
          'download/v1.0.8/mfuns-flutter-1.0.8.apk'),
      'https://hub.wgen.top/https://github.com/ymltsh/Mfuns_Flutter/'
      'releases/download/v1.0.8/mfuns-flutter-1.0.8.apk',
    );
  });
}
