/// 导出内容底部的开源项目说明（Markdown 与长图共用同一份文案与地址）。
class ExportFooter {
  const ExportFooter._();

  static const projectName = 'Mfuns Flutter';
  static const repositoryUrl = 'https://github.com/ymltsh/Mfuns_Flutter';

  /// 图片导出中展示的短地址（去掉协议头，低调排版）。
  static const repositoryHost = 'github.com/ymltsh/Mfuns_Flutter';

  /// 一句话项目描述（与 README 保持一致）。
  static const description =
      '本项目是一个由社区支持的Material Design风格的Mfuns客户端，完全开源免费无广告，请点个star吧！';

  /// Markdown 版页脚。
  static const markdown = '''
---

## 关于 Mfuns Flutter

本文由 Mfuns Flutter 导出。

$description

项目地址：
$repositoryUrl
''';
}
