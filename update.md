# 更新发布流程（Update.md）

本文档说明 Mfuns Flutter 的版本发布流程与「检查更新」接口的维护方式。
Environment：path
默认情况只推送version.json和GitHub 发布页 | `https://github.com/ymltsh/Mfuns_Flutter/releases/latest`，代码提交全仓库提交耗时过长，所以默认不这么做。

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
      "windows": "https://github.com/ymltsh/Mfuns_Flutter/releases/download/v1.3.1/mfuns-flutter-windows-1.3.1.zip"
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
| `latest.urls.windows` | 可选 | Windows zip 下载直链 |
| `latest.page` | 可选 | 发布页链接，缺省回退到 releases/latest |
| `history[]` | 推荐 | 历史版本列表（结构同 latest，不含 urls 也可），按新旧倒序 |

版本比较规则：先比较 `version` 三段数值，相同再比较 `build`，均相同视为无更新。

## 二、版本发布流程

> 前置条件：能推送 `main` 分支的 Git 凭据（`git push` 通过即可，发布资产上传使用同一凭据的 GitHub Token）。

### 0. 推荐：一键发布工具（release.py）

仓库根目录的 `release.py`（单文件、仅标准库）自动完成以下全部流程：
更新版本号 → analyze/test → 构建 APK → 构建 Windows → 打包 zip → 创建 GitHub
Release 并上传资产 → 更新 version.json → 提交并推送。

**引导模式**（无参数运行，交互式问答）：

```powershell
python release.py
```

按提示输入新版本号、构建号、发布类型（1 正式版 / 2 Beta / 3 Beta2）、
发布标题与多行发布说明（空行结束）即可；构建前会自动询问是否结束运行中的
`mfuns_flutter` 实例（避免 exe 锁定）。

**CLI 模式**（非交互）：

```powershell
set FLUTTER_BIN=C:\path\to\flutter\bin\flutter.bat   # flutter 不在 PATH 时必须设置

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
| `--skip-build` | 跳过构建与打包，复用现有产物（需已存在） |
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
flutter build apk --release          # Android → build/app/outputs/flutter-apk/app-release.apk
flutter build windows                # Windows → build/windows/x64/runner/Release/
```

Windows 发布前先确认没有正在运行的旧实例（否则 exe 被占用无法链接）。

### 3. 创建 GitHub Release

使用 `gh` CLI 或 GitHub API 创建 tag 与 release（tag 名建议 `v1.3.1`），并上传两个资产：

- `mfuns-flutter-1.3.1.apk`（Android）
- `mfuns-flutter-windows-1.3.1.zip`（Windows Release 目录打包，**不含目录内旧的 Release.zip**）

> 注意：资产上传走 `uploads.github.com`（不是 `api.github.com`），否则返回 404。

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
| release.py 提示无 GitHub Token | 先 `git push` 一次保存凭据，或使用 `--token` 显式传入 |
| 发布后构建号与产物不一致 | 避免重复运行 release.py；用 `--build N` 显式指定构建号 |
| Windows 构建失败（exe 被占用） | 关闭运行中的 mfuns_flutter 后重试（工具引导模式会自动询问） |
