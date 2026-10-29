# 更新发布流程（Update.md）

本文档说明 Mfuns Flutter 的版本发布流程与「检查更新」接口的维护方式。
Environment：path
默认流程构建三种 ABI 的 Android APK、Windows 安装程序和便携包，上传至 GitHub Release 草稿，全部上传后公开发布，再只推送 `version.json`。源码提交按项目约定单独处理。

## 一、检查更新接口

### 访问地址

| 项目 | 值 |
| ---- | ---- |
| 源地址 | `https://raw.githubusercontent.com/ymltsh/Mfuns_Flutter/main/version.json` |
| 加速站地址（App 实际使用） | `https://hub.wgen.top/https://raw.githubusercontent.com/ymltsh/Mfuns_Flutter/main/version.json` |
| GitHub 发布页 | `https://github.com/ymltsh/Mfuns_Flutter/releases/latest` |

App 启动后不主动拉取；用户在「设置 → 检查更新」时通过**加速站地址**读取 `version.json`，与当前版本（`AppConfig.appVersion` / `appBuild`）比较：

- 清单版本更新 → 弹窗展示更新内容与下载按钮
- 版本一致或更新 → 提示「已是最新版本」
- 读取失败 → 提示错误并支持重试

### 清单格式（version.json）

```json
{
  "latest": {
    "version": "1.3.1",
    "build": 35,
    "name": "Mfuns Flutter v1.3.1",
    "date": "2026-08-27",
    "notes": "更新内容说明（\n 可换行）",
    "urls": {
      "android": "https://github.com/ymltsh/Mfuns_Flutter/releases/download/v1.3.1/mfuns-flutter-1.3.1.apk",
      "windows": "https://github.com/ymltsh/Mfuns_Flutter/releases/download/v1.3.1/mfuns-flutter-setup-1.3.1.exe",
      "windows_portable": "https://github.com/ymltsh/Mfuns_Flutter/releases/download/v1.3.1/mfuns-flutter-windows-1.3.1.zip"
    },
    "page": "https://github.com/ymltsh/Mfuns_Flutter/releases/tag/v1.3.1"
  },
  "history": [
    {
      "version": "1.2.9",
      "build": 34,
      "name": "Mfuns Flutter v1.2.9",
      "date": "2026-08-27",
      "notes": "历史版本更新说明"
    }
  ]
}
```

字段说明：

| 字段 | 必填 | 说明 |
| ---- | ---- | ---- |
| `latest.version` | ✅ | 最新版本号，三段式 `x.y.z` |
| `latest.build` | ✅ | 构建号（与 pubspec 的 `+n` 一致），用于同版本号的先后判断 |
| `latest.name` | ✅ | 发布标题 |
| `latest.date` | 可选 | 发布日期 |
| `latest.notes` | 可选 | 更新内容，`\n` 换行 |
| `latest.urls.android` | 可选 | Android APK 下载直链（无则不显示下载按钮） |
| `latest.urls.windows` | 可选 | Windows 安装程序 `.exe` 下载直链 |
| `latest.urls.windows_portable` | 可选 | Windows 便携版 `.zip` 下载直链 |
| `latest.page` | 可选 | 发布页链接，缺省回退到 releases/latest |
| `history[]` | 推荐 | 历史版本列表（结构同 latest，不含 urls 也可），按新旧倒序 |

版本比较规则：先比较 `version` 三段数值，相同再比较 `build`，均相同视为无更新。

## 二、版本发布流程

> 前置条件：能推送 `main` 分支的 Git 凭据（`git push` 通过即可，发布资产上传使用同一凭据的 GitHub Token）。

### 0. 推荐：一键发布工具（release.py）

仓库根目录的 `release.py`（单文件、仅标准库）自动完成以下全部流程：
更新版本号 → analyze/test → 构建 APK → 构建 Windows → 打包便携 ZIP 与安装程序
→ 创建 GitHub Release 并上传资产 → 更新 version.json → 提交并推送。

Windows 安装程序使用 Inno Setup 6 编译。发布机需预先安装 Inno Setup 6，确保
`ISCC.exe` 在 PATH 中，或设置 `INNO_SETUP_COMPILER` 指向该文件。安装程序按当前用户安装到
`%LOCALAPPDATA%\Programs\Mfuns Flutter`，创建开始菜单快捷方式，可选创建桌面快捷方式，
并注册卸载项；不需要管理员权限。Release 仍同时提供便携 ZIP。

**引导模式**（无参数运行，交互式问答）：

```powershell
python release.py
```

按提示输入新版本号、构建号、发布类型（1 正式版 / 2 Beta / 3 Beta2）、
发布标题与多行发布说明（空行结束）即可；构建前会自动询问是否结束运行中的
`mfuns_flutter` 实例（避免 exe 锁定）。

**CLI 模式**（非交互）：

```powershell
$env:FLUTTER_BIN = 'C:\path\to\flutter\bin\flutter.bat'  # flutter 不在 PATH 时设置
$env:INNO_SETUP_COMPILER = 'C:\path\to\Inno Setup 6\ISCC.exe'  # ISCC 不在 PATH 时设置

python release.py --version 1.3.1 --notes "更新说明"             # 正式版
python release.py --version 1.3.1 --beta --notes "测试"          # Beta
python release.py --version 1.3.1 --beta2 --notes "测试"         # Beta2
python release.py --version 1.3.1 --dry-run                       # 仅预览不执行
python release.py --version 1.3.1 --skip-build --no-push          # 复用产物、不推送
```

常用参数：

| 参数 | 说明 |
| ---- | ---- |
| `--version` | 新版本号，如 `1.3.1`（缺省自动建议下一位） |
| `--build` | 构建号（缺省为当前 +1；**重复运行会漂移，建议显式指定**） |
| `--beta` / `--beta2` | 预发布，tag 与资产名自动带 `-beta` / `-beta2` 后缀 |
| `--name` / `--notes` | 发布标题 / 发布说明（多行用 `\n`） |
| `--repo` / `--token` | 仓库（默认读 git remote）/ Token（默认读 git 凭据） |
| `--dry-run` | 仅打印发布计划，不执行 |
| `--skip-build` | 跳过构建与打包，复用现有 APK、对应版本的便携 ZIP 和安装程序 |
| `--skip-checks` | 跳过 analyze / test |
| `--no-push` | 不提交/推送 version.json |

> 注意：CLI 模式会直接结束运行中的 `mfuns_flutter` 实例以完成 Windows 链接。

### 1. 更新版本号

编辑 `pubspec.yaml`：

```yaml
version: 1.3.1+35
```

并同步更新 `lib/core/config/app_config.dart`：

```dart
static const appVersion = '1.3.1';
static const appBuild = 35;
```

> 版本号与构建号必须与 pubspec 保持一致，否则更新比较会误判。

**版本号建议（可选规则，按需采用）**

- **语义化版本（默认）**：`x.y.z`（主版本.次版本.修订），构建号 `+n`，如 `1.4.0+38`。
- **星座发布规则**：只有版本号第二位（次版本号 `y`）变化时才更新星座代号。代号按固定列表顺序推进（列表用尽后回到开头循环），并写入发布标题与 `version.json` 的 `latest.name`，例如 v1.4.0 = 英仙座（Per）。
  - 固定星座列表（自 v1.4.0 起顺序推进）：

    | 序号 | 星座 | 缩写（代号） |
    | ---- | ---- | ---- |
    | 1 | 英仙座 | Per（v1.4.0 已用） |
    | 2 | 仙后座 | Cas |
    | 3 | 天鹅座 | Cyg |
    | 4 | 天鹰座 | Aql |
    | 5 | 猎户座 | Ori |
    | 6 | 大熊座 | UMa |
    | 7 | 小熊座 | UMi |
    | 8 | 狮子座 | Leo |
    | 9 | 天琴座 | Lyr |
    | 10 | 仙女座 | And |

  - 仅当第一位主版本号相同、第二位次版本号变化（如 1.4.x → 1.5.x）时，取列表下一个星座。
  - 第三位补丁版本号、构建号和预发布后缀变化（如 1.5.0 → 1.5.1、`+44` → `+45`、`1.5.1-beta`）均沿用当前星座代号。因此 1.5.x 仍为仙后座 `Cas`（App 彩蛋中显示为 `CAS`）。
  - 第一位主版本号变化（如 1.x → 2.x）时不按此规则自动推进，由当次发布计划单独确定星座代号。
  - 发布标题示例：`Mfuns Flutter v1.4.0 英仙座`；发布说明开头可注明代号。

#### 版本星座彩蛋更新（必做）

App 内的彩蛋入口为「设置 → 关于」，在 2 秒间隔内连续点击 Logo 7 次触发。彩蛋会全屏覆盖 App，依次播放：群星出现 → 当前星座主星逐颗点亮 → 星座连线绘制 → 代号、版本号与 Slogan 浮现。

`release.py` 目前不会自动更新彩蛋的星座数据和星图。当第二位次版本号变化时，需在构建前手动完成以下步骤：

1. 确认此次发布是第二位次版本号变化，再按固定星座列表确定新代号；补丁版本、构建号和预发布后缀变化不切换代号。
2. 修改 `lib/core/config/version_constellation.dart` 中的 `VersionConstellation.current`：
   - `releaseLine`：当前 `x.y` 发布线；
   - `name`：星座中文名；
   - `latinName`：彩蛋中显示的大写代号；
   - `tagline`：一句与该星座象征意义相符的简体中文 Slogan，避免只复述星座名。
3. 修改 `lib/features/settings/widgets/version_constellation_dialog.dart`：
   - 将绘制器命名更新为当前星座；
   - 按星座的辨识性形状更新 `_stars` 归一化坐标；
   - 更新 `_links` 连线顺序，确保动画不会出现跳线或错连；
   - 保持「群星 → 主星 → 连线 → 文字」的时序，不要让文字早于星图出现。
4. 更新 `test/widget_test.dart` 中彩蛋用例的中文星座名和英文代号断言。
5. 同步 GitHub Release 标题、发布说明和 `version.json` 中的 `latest.name`，确保对外代号与 App 彩蛋一致。

当前 1.5.x 彩蛋配置示例：

```dart
static const current = VersionConstellation(
  releaseLine: '1.5',
  name: '仙后座',
  latinName: 'CAS',
  tagline: '守望北天，于长夜中指引方向。',
);
```

彩蛋修改后至少执行：

```powershell
dart format lib/core/config/version_constellation.dart lib/features/settings/widgets/version_constellation_dialog.dart test/widget_test.dart
flutter analyze
flutter test test/widget_test.dart
```

并手动检查一次手机竖屏、手机横屏或 Windows 窄窗口，确认星图居中、文字无溢出、关闭按钮可用，且动画结束后显示的版本号与 `AppConfig` 一致。

### 2. 构建产物

```powershell
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64          # Android → build/app/outputs/flutter-apk/app-<ABI>-release.apk
flutter build windows                # Windows → build/windows/x64/runner/Release/
```

`release.py` 随后会把 Windows Release 目录打成便携 ZIP，并调用
`installer/windows/MfunsFlutter.iss` 生成安装程序。Windows 发布前先确认没有正在运行的旧实例
（否则 exe 被占用无法链接）。

脚本要求 Windows Release 目录包含 `mfuns_flutter.exe`。安装 Inno Setup 6 后，
可用下列命令检查发布计划，再执行完整流程：

```powershell
python release.py --version 1.6.6 --build 62 --notes '更新说明' --dry-run
python release.py --version 1.6.6 --build 62 --notes '更新说明'
```

打包完成后，本地保留以下产物；`--skip-build` 会按本次版本后缀查找这五个文件，
不会重新打包，复用前需确认它们确实来自当前版本的构建：

| 产物 | 本地路径 |
| ---- | -------- |
| Android ARM32 | `build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk` |
| Android ARM64 | `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` |
| Android x86_64 | `build/app/outputs/flutter-apk/app-x86_64-release.apk` |
| Windows 安装程序 | `build/windows/installer/mfuns-flutter-setup-1.6.6.exe` |
| Windows 便携版 | `mfuns-flutter-windows-1.6.6.zip` |

### 3. 创建 GitHub Release

使用 `gh` CLI 或 GitHub API 创建 tag 与 release（tag 名建议 `v1.3.1`），先创建草稿并上传五个资产，确认齐全后公开 Release：

- `mfuns-flutter-1.3.1-armeabi-v7a.apk`（Android ARM32）
- `mfuns-flutter-1.3.1-arm64-v8a.apk`（Android ARM64）
- `mfuns-flutter-1.3.1-x86_64.apk`（Android x86_64）
- `mfuns-flutter-setup-1.3.1.exe`（Windows 基础安装程序，按当前用户安装）
- `mfuns-flutter-windows-1.3.1.zip`（Windows 便携版，Release 目录打包，**不含目录内旧的 Release.zip**）

> 注意：资产上传走 `uploads.github.com`（不是 `api.github.com`），否则返回 404。

### Android 架构选择与旧版迁移

后续发布不再生成通用大 APK，也不把原生 `.so` 库作为独立文件下载。每个 APK 都是可完整安装、只包含单种 ABI 原生库的安装包。

新清单的 `latest.urls` 增加 `android_abis`，三种架构均必须有对应的已上传 APK：

```json
{
  "android": "https://github.com/ymltsh/Mfuns_Flutter/releases/download/v1.6.8/mfuns-flutter-1.6.8-arm64-v8a.apk",
  "android_abis": {
    "armeabi-v7a": "https://github.com/ymltsh/Mfuns_Flutter/releases/download/v1.6.8/mfuns-flutter-1.6.8-armeabi-v7a.apk",
    "arm64-v8a": "https://github.com/ymltsh/Mfuns_Flutter/releases/download/v1.6.8/mfuns-flutter-1.6.8-arm64-v8a.apk",
    "x86_64": "https://github.com/ymltsh/Mfuns_Flutter/releases/download/v1.6.8/mfuns-flutter-1.6.8-x86_64.apk"
  }
}
```

- 新客户端按 Android `Build.SUPPORTED_ABIS` 的顺序自动选择已提供的兼容 APK，包括 64 位 CPU 配 32 位系统的设备。
- 无法读取架构或没有兼容包时，不猜测 ARM64；更新弹窗提示用户打开发布页手动选择。
- 旧清单仍支持 `urls.android` 通用 APK 直链。新版清单的该字段默认指向 ARM64（arm64-v8a）APK，旧客户端直接下载该包；32 位系统与 x86_64 用户可通过发布页选择兼容包，安装新客户端后自动匹配。
- `--skip-build` 必须具备全部三种分架构 APK，脚本会检查每个包的原生库仅包含目标 ABI，并含 `libapp.so` 和 `libflutter.so`，不会复用旧通用包。
- Flutter 分 ABI APK 的原生 `versionCode` 带有架构偏移；应用更新比较仍使用 `AppConfig.appBuild` 与清单中的基础构建号。后续应持续分 ABI 发布，勿直接回退到基础构建号更低的旧通用包。
- 安装包文件名、清单 URL 与上传资产必须一致；先上传全部五项资产并公开 Release，再更新并推送清单。

### 4. 更新 version.json

- `latest` 改为新版本信息（下载链接、发布页、更新内容）
- 把上一版 `latest` 的内容追加到 `history` 头部（可去掉 urls，仅保留版本/日期/说明）
- 提交并推送：

```powershell
git add version.json
git commit -m "Bump update manifest to v1.3.1"
git push origin main
```

### 5. 验证接口

```powershell
Invoke-RestMethod "https://hub.wgen.top/https://raw.githubusercontent.com/ymltsh/Mfuns_Flutter/main/version.json"
```

确认 `latest` 为新版本号、下载链接可访问。

### 6. 回归检查（App 内）

- 旧版本安装包 →「设置 → 检查更新」应提示发现新版本，展示更新内容与下载按钮
- 同版本号重装 → 提示「已是最新版本」
- 断网 / 接口异常 → 提示失败并支持重试

## 三、常见问题

| 问题 | 处理 |
| ---- | ---- |
| 检查更新一直失败 | 确认 version.json 已推送、加速站地址拼写正确、本机网络可访问 `hub.wgen.top` |
| 提示有更新但没下载按钮 | `latest.urls` 缺少当前平台对应字段（如 Windows 上缺 `windows` 链接） |
| 版本号一致仍提示更新 | 检查 `AppConfig.appBuild` 是否与 pubspec 的 `+n` 同步 |
| 下载链接 404 | 确认资产文件名与 `urls` 中的下载直链完全一致（含文件名与 tag） |
| release.py 找不到 flutter | 设置 `FLUTTER_BIN` 环境变量指向 `flutter.bat`，或将其加入 PATH |
| release.py 找不到 ISCC.exe | 安装 Inno Setup 6，或设置 `INNO_SETUP_COMPILER` 指向 `ISCC.exe` |
| release.py 提示无 GitHub Token | 先 `git push` 一次保存凭据，或使用 `--token` 显式传入 |
| 发布后构建号与产物不一致 | 避免重复运行 release.py；用 `--build N` 显式指定构建号 |
| Windows 构建失败（exe 被占用） | 关闭运行中的 mfuns_flutter 后重试（工具引导模式会自动询问） |
