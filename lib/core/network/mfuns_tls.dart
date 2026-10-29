import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Temporary trust-store compatibility for Mfuns' Sectigo E46 API chain.
///
/// Keeps the operating system's trusted roots and normal TLS validation.
/// The extra root is used only by HttpClients explicitly created here.
class MfunsTls {
  MfunsTls._();

  static const enabled = bool.fromEnvironment(
    'MFUNS_E46_COMPAT',
    defaultValue: true,
  );

  static const _certificateAsset = 'assets/certs/sectigo-e46.pem';

  // Self-signed Sectigo Public Server Authentication Root E46.
  // Published certificate SHA-256 (DER), not a site/leaf fingerprint.
  static const certificateSha256 =
      'c90f26f0fb1b4018b22227519b5ca2b53e2ca5b3be5cf18efe1bef47380c5383';

  static SecurityContext? _context;

  static Future<void> initialize({AssetBundle? bundle}) async {
    if (kIsWeb || !enabled) return;

    final pem = await (bundle ?? rootBundle).loadString(_certificateAsset);
    final encoded = pem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s+'), '');
    final der = base64Decode(encoded);
    if (sha256.convert(der).toString() != certificateSha256) {
      throw StateError('Sectigo E46 certificate fingerprint mismatch');
    }

    final context = SecurityContext(withTrustedRoots: true);
    // dart:io requires a single DER certificate on iOS; other platforms
    // accept PEM. Do not use withTrustedRoots:false or badCertificateCallback.
    context.setTrustedCertificatesBytes(
      Platform.isIOS ? der : utf8.encode(pem),
    );
    _context = context;
  }

  static HttpClient createHttpClient() => HttpClient(context: _context);
}
