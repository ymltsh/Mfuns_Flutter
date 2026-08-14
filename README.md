# Mfuns Flutter

Mfuns 社区（mfuns.net）的非官方 Flutter 客户端，Android 优先，同时支持 Windows 桌面端。

## 功能特性

**浏览**
- 首页推荐流 / 热榜 / 分区（分类树与分区内容）
- 全站动态时间线（关注 / 最新 / 时间线，支持排序切换）
- 内容搜索（文章 / 视频）
- 文章与视频详情、视频多清晰度播放（360p–1080p 直链）

**互动**
- 账号密码登录、会话安全存储与自动恢复
- 点赞 / 点踩 / 收藏 / 评论、评论回复、评论删除（长按）
- 评论表情包（私有表情包）与图片发布、消息私信与通知中心
- 投稿管理：文章发布/编辑、视频本地上传（阿里云 OSS + VOD）、动态发布
- 用户主页（动态 / 文章 / 视频）

**播放体验**
- 竖屏播放高度限制、横屏自动分栏（左播放器 + 右信息）
- 弹幕：滚动弹幕（多轨道）+ 置顶/底部弹幕，支持透明度 / 字号设置
- 播放器横屏沉浸式布局、状态栏适配

**个性化**
- 自定义主题色（预设色板 + 自定义色号，默认洛天依蓝 `#66CCFF`）
- 默认清晰度、弹幕偏好设置
- 我的页面统计（历史 / 收藏夹 / 投稿数量自动加载）

## 技术栈

- Flutter 3.24 / Dart 3.5
- 依赖：`video_player`（Android/iOS）+ `video_player_win`（Windows）、`flutter_secure_storage`、`shared_preferences`、`image_picker`、`file_picker`、`html`、`flutter_markdown_plus`、`crypto`
- 视频上传：VOD 凭证（`/v1/contribute/video/get_upload_auth`）→ 标准 OSS 签名 PUT（纯 Dart 实现）→ `/v1/contribute/video/upload_complete`
- 无第三方状态管理，基于 `ChangeNotifier`（`AppController`）+ `ThemeExtension` 主题

## 本地开发

```bash
flutter pub get
flutter run                  # Android / Windows
flutter test                 # 运行测试
flutter analyze
```

打包：

```bash
flutter build apk --release          # Android APK
flutter build windows --release      # Windows exe
```

可选：覆盖默认 User-Agent（兼容性测试）：

```bash
flutter run --dart-define=MFUNS_USER_AGENT='Mozilla/5.0 (...)'
```

## 项目结构

```
lib/
├── main.dart                  # 入口（全局 edge-to-edge 沉浸式）
├── app/                       # 应用壳、主界面、AppController
├── core/
│   ├── config/                # 配置与用户偏好（默认清晰度、弹幕设置）
│   ├── emoji/                 # 私有表情包加载与缓存
│   ├── network/               # API 客户端、VOD/OSS 上传
│   ├── theme/                 # 主题构建与持久化
│   └── widgets/               # 图片预览、表情选择、内联输入、内容 spans 等共享组件
└── features/
    ├── auth/                  # 登录与会话
    ├── content/               # 富文本内容渲染（HTML/Quill → Markdown）
    ├── contribute/            # 投稿管理（列表 / 详情 / 编辑器 / 视频上传）
    ├── feed/                  # 动态发布
    ├── home/                  # 首页、动态、推荐、评论等数据仓库与模型
    ├── latest/                # 最新内容聚合源
    ├── message/               # 私信与通知中心
    ├── settings/              # 设置页（资料编辑、偏好、缓存）
    ├── user/                  # 用户主页
    └── video/                 # 播放器、弹幕、评论等
```

## API 约定

- 主机：`https://api.mfuns.net`，路径以 `/v1/` 开头
- 认证：`Authorization` 直接携带社区 token（无 `Bearer` 前缀）
- 登录：`POST /v1/auth/login`（form 编码），会话经 `/v1/user/info` 校验
- 表情包：`GET /v1/emoji_pack/list`、`GET /v1/emoji_pack/face_text`
- 资源类型：`0` 文章 / `1` 视频 / `4` 评论·动态
- 详细接口契约见 `mfuns_api_docs.md`

## 参考

- 接口抓包与文档：`mfuns_api_docs.md`、`*.har`
- 服务端接口参考实现：[Mfuns-MCP](https://github.com/)（`latest-mfuns/` 为聚合服务）

## 免责声明

本项目为非官方客户端，仅用于学习交流；所有数据来源于 Mfuns 社区公开接口。
