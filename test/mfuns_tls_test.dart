import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfuns_flutter/core/network/mfuns_tls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'E46 bundled root has the expected public SHA-256 fingerprint',
    () async {
      final pem = await rootBundle.loadString('assets/certs/sectigo-e46.pem');
      final der = base64Decode(
        pem
            .replaceAll('-----BEGIN CERTIFICATE-----', '')
            .replaceAll('-----END CERTIFICATE-----', '')
            .replaceAll(RegExp(r'\s+'), ''),
      );

      expect(sha256.convert(der).toString(), MfunsTls.certificateSha256);
    },
  );

  test(
    'API and default image clients never set a certificate bypass',
    () async {
      await MfunsTls.initialize();
      final contexts = <SecurityContext?>[];
      final clients = <_ObservedClient>[];
      HttpOverrides.runZoned(
        () {
          MfunsTls.createHttpClient();
          HttpClient();
        },
        createHttpClient: (context) {
          contexts.add(context);
          final client = _ObservedClient();
          clients.add(client);
          return client;
        },
      );
      expect(contexts.first, MfunsTls.enabled ? isNotNull : isNull);
      expect(contexts.last, isNull);
      expect(clients.every((client) => client.bypassAssignments == 0), isTrue);
    },
  );

  test(
    'tampered certificate is rejected before replacing the trust context',
    () async {
      if (!MfunsTls.enabled) return;
      await MfunsTls.initialize();
      await expectLater(
        MfunsTls.initialize(bundle: _TamperedBundle()),
        throwsStateError,
      );
    },
  );
}

class _TamperedBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(
      utf8.encode(
        '-----BEGIN CERTIFICATE-----\nAA==\n-----END CERTIFICATE-----',
      ),
    ),
  );
}

class _ObservedClient implements HttpClient {
  int bypassAssignments = 0;
  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? callback,
  ) {
    bypassAssignments++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
