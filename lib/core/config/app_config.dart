class AppConfig {
  const AppConfig._();

  static const apiHost = 'api.mfuns.net';

  /// Public, read-only latest-content source. Keep it separate from
  /// [apiHost]: Mfuns community Authorization is never sent to this host.
  static const latestMfunsHost = 'mfuns.wgen.top';

  /// A standard mobile Chrome UA. Override at build time when compatibility
  /// testing identifies a more suitable value for a target device.
  static const userAgent = String.fromEnvironment(
    'MFUNS_USER_AGENT',
    defaultValue: 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
  );
}
