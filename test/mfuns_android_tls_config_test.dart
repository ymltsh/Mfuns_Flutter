import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/mfuns_tls.dart';

void main() {
  test(
    'Android Mfuns domain TLS policy uses verified Sectigo E46 root',
    () async {
      final manifest = await File('android/app/src/main/AndroidManifest.xml')
          .readAsString();
      final xml = await File(
        'android/app/src/main/res/xml/mfuns_network_security_config.xml',
      ).readAsString();
      final nativePem = await File(
        'android/app/src/main/res/raw/mfuns_sectigo_e46.pem',
      ).readAsString();
      final flutterPem = await File('assets/certs/sectigo-e46.pem')
          .readAsString();

      expect(
        manifest,
        contains(
          'android:networkSecurityConfig="@xml/mfuns_network_security_config"',
        ),
      );
      expect(
        xml,
        contains('<domain includeSubdomains="true">mfuns.net</domain>'),
      );
      expect(xml, contains('<certificates src="system" />'));
      expect(xml, contains('<certificates src="@raw/mfuns_sectigo_e46" />'));
      expect(xml, contains('cleartextTrafficPermitted="false"'));
      expect(xml, isNot(contains('<base-config')));
      expect(nativePem, flutterPem);

      final der = base64Decode(
        nativePem
            .replaceAll('-----BEGIN CERTIFICATE-----', '')
            .replaceAll('-----END CERTIFICATE-----', '')
            .replaceAll(RegExp(r'\s+'), ''),
      );
      expect(sha256.convert(der).toString(), MfunsTls.certificateSha256);
    },
  );
}
