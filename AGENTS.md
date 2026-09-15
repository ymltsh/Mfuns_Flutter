# AGENTS.md

本文件适用于仓库根目录及其全部子目录，供在本项目中工作的自动化编码代理参考。若子目录中存在更具体的 `AGENTS.md`，则以更具体的文件为准。

## 项目概览

- 本项目是 Mfuns 社区的 Flutter 客户端，包名为 `mfuns_flutter`。
- 主要目标平台为 Android 和 Windows；修改公共 Dart 代码时也要避免无意破坏 iOS 等 Flutter 平台。
- 当前基线为 Flutter 3.24、Dart 3.5（`pubspec.yaml` 要求 Dart `^3.5.4`）。不要引入需要更高 SDK、Android Gradle Plugin 或 Kotlin 基线的依赖。
- 应用使用 Material Design，无第三方状态管理框架。全局状态主要由 `AppController`、`ChangeNotifier` 和 `ValueNotifier` 管理，数据访问通过 Repository / Service 层完成。
- Environment：C:\Users\YGen\Documents\flutter
- "C:\Users\YGen\Desktop\Doc\Mfuns-Flutter\.idea\mfuns_api_docs.md"
## 目录职责

- `lib/main.dart`：启动流程、平台服务初始化、全局导航和深链入口。
- `lib/app/`：应用壳、主导航、全局控制器。
- `lib/core/`：跨功能共享的配置、网络、下载、媒体、通知、主题和组件。
- `lib/features/<feature>/`：按业务功能组织的页面、模型和仓库。新功能优先放入对应 feature，不要继续扩大应用壳。
- `test/`：单元测试和 Widget 测试；`integration_test/`：端到端测试。
- `android/`、`ios/`、`windows/`：平台工程。仅在功能确实需要原生配置时修改。
- `assets/`：随应用打包的静态资源；新增资源后同步更新 `pubspec.yaml`。
- `latest-mfuns-2/`、`build/`、`.dart_tool/` 和各平台生成目录不属于日常 Dart 功能修改范围。

## 开发原则

- 先阅读将要修改的页面、其 Repository、相关模型和测试，沿用已有命名、错误处理和组件风格。
- 保持改动聚焦。不要顺手重构无关代码，也不要覆盖或回退工作区中已有的未提交修改。
- UI 负责渲染与交互，网络请求、JSON 解析和持久化应留在 Repository 或 `core/` 服务中；可测试的纯逻辑应从 Widget 中提取。
- 延续现有的空安全、`const`、不可变模型和显式类型风格。异步回调更新界面前检查 `mounted`，持有监听器、控制器或计时器的 State 必须在 `dispose` 中释放。
- 用户可见文本以简体中文为主。对不直观的平台兼容、API 差异或业务规则写简短注释，避免复述代码。
- 优先复用 `lib/core/widgets/`、主题中的颜色/间距能力和现有内容渲染组件，不在页面内复制近似实现或硬编码新的视觉体系。
- 保持手机竖屏和横屏/Windows 宽屏布局可用；避免只按固定屏幕宽度设计。

## API、认证与数据解析

- Mfuns API 主机在 `AppConfig.apiHost` 中统一维护，接口路径通常以 `/v1/` 开头；不要在页面中散落主机地址。
- 社区 token 的 `Authorization` 值不带 `Bearer` 前缀。不要记录、打印、提交 token、Cookie、密码、上传凭证或完整授权请求头。
- `latestMfunsHost` 是独立的只读聚合源，绝不能向该主机发送 Mfuns 社区认证信息。
- 服务端字段可能有历史形态。修改 JSON 解析时保留现有兼容分支和安全转换策略，并为缺字段、不同数值/字符串表示及嵌套结构补测试。
- 资源类型约定：`0` 为文章、`1` 为视频、`4` 为评论/动态。不要仅凭页面外观混用文章、视频和动态模型。
- 网络或平台能力失败时给出可理解的 UI 状态；只有现有启动代码明确将能力视为可选时，才可静默降级。

## 依赖、版本与生成文件

- 添加或升级依赖前检查 Flutter 3.24、Dart 3.5、AGP 8.1 和 Kotlin 1.8.22 的兼容性，并说明新增依赖的必要性。
- 修改依赖时提交对应的 `pubspec.lock`，不要随意删除 `dependency_overrides`；其中包含为现有 Android 工具链保留的兼容性约束。
- 版本发布改动需同步核对 `pubspec.yaml`、`lib/core/config/app_config.dart` 和 `version.json`，但普通功能修改不要自行提升版本号。
- 不编辑或提交 `build/`、`.dart_tool/`、`.flutter-plugins*` 等生成产物。平台插件注册文件应由 Flutter 工具生成，而非手工维护。
- 不提交网络抓包、密钥、签名材料、个人路径或本地缓存。

## 测试与验证

完成改动后，按影响范围运行最小充分验证：

```bash
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
```

- 开发过程中可先运行单个测试，例如 `flutter test test/<name>_test.dart`，交付前再扩大到相关测试集。
- 修改 JSON 解析、分页/合并、下载状态机、播放协调、导出、深链或布局切换时，优先补充对应的回归测试。
- 纯格式检查失败时先运行 `dart format <changed-files>`，不要为了通过分析器而全局禁用 lint。
- 涉及 Android、Windows 或插件配置的修改，应尽可能执行对应平台的构建或至少说明未验证的部分。
- 测试通常不得依赖真实账号、生产写操作或不稳定网络；使用构造数据、mock/fake 或现有的可注入边界。

## 交付要求

- 总结改了什么、为什么，以及实际运行过哪些验证命令。
- 明确报告仍存在的失败、平台未验证项或需要人工检查的行为，不要声称未执行的测试已通过。
- 除非用户明确要求，不创建发布、提交、标签，不上传构建产物，也不更改远端服务数据。
