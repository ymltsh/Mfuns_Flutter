class AppConfig {
  const AppConfig._();

  static const apiHost = 'api.mfuns.net';

  /// Public, read-only latest-content source. Keep it separate from
  /// [apiHost]: Mfuns community Authorization is never sent to this host.
  static const latestMfunsHost = 'mfuns.wgen.top';

  /// 当前应用版本号与构建号（与 pubspec.yaml 保持一致）。
  static const appVersion = '1.2.6';
  static const appBuild = 31;

  /// 默认 GitHub 加速地址（用户可在设置中自定义）。
  static const defaultAcceleratorBase = 'https://hub.wgen.top/';

  /// 更新清单源地址（raw.githubusercontent.com），实际请求时拼接加速地址。
  static const updateManifestRawUrl =
      'https://raw.githubusercontent.com/ymltsh/Mfuns_Flutter/main/version.json';

  /// GitHub 发布页（用于查看最新 release）。
  static const releasePageUrl =
      'https://github.com/ymltsh/Mfuns_Flutter/releases/latest';

  /// A standard mobile Chrome UA. Override at build time when compatibility
  /// testing identifies a more suitable value for a target device.
  static const userAgent = String.fromEnvironment(
    'MFUNS_USER_AGENT',
    defaultValue: 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
  );
}
