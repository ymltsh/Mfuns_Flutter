# Mfuns-Flutter 客户端方案

## 1. 目标与范围

构建 Android 优先、可扩展到 iOS 的 Mfuns 原生 Flutter 客户端。第一阶段以「浏览、播放、搜索、登录后的个人操作」形成闭环；仅在已验证且获得服务端许可的接口上实现写操作。

### MVP（P0）

- 首页推荐、分区/榜单、动态流
- 视频详情：封面、简介、标签、选集、相关推荐、评论列表
- 播放：HLS/DASH/直链中实际可用的一种或多种，清晰度选择、倍速、续播
- 搜索（视频、用户、标签，以接口能力为准）
- 账号登录、会话恢复、个人资料、收藏/历史
- 深色模式、错误页、骨架屏、网络重试

### 后续（P1/P2）

- 评论发布/回复、点赞、关注、通知
- 离线缓存或下载（仅在平台规则与媒体授权允许时）
- 投稿、私信、直播、社区管理能力：单独评估接口权限、风控和合规性后再排期

## 2. 现状检查（2026-08-10）

| 项目 | 结果 | 处理建议 |
| --- | --- | --- |
| 工作目录 | 空目录，尚未初始化 Git | 初始化仓库并建立 CI |
| Flutter / Dart | 已安装于 `C:\\Users\\YGen\\Documents\\flutter`：Flutter 3.24.5 stable / Dart 3.5.4；未加入 PATH | 将 `flutter\\bin` 加入当前用户 PATH；网络恢复后执行 `flutter doctor -v` 并评估升级 stable |
| Java | OpenJDK 21.0.5 | 先以 JDK 21 构建；仅在 Gradle/Android 插件报兼容错误时切换 JDK 17 LTS |
| Android SDK | 已安装 platforms 33–36、build-tools 33/34/35、API 35 模拟器镜像 | 设定 `ANDROID_SDK_ROOT`，创建 API 35 模拟器 |
| ADB | 可执行文件位于 `C:\\Users\\YGen\\Documents\\platform-tools\\adb.exe` | 将 SDK 的 `platform-tools` 纳入 PATH，连接设备后复核 |

## 3. 站点/API 探测结论

目标入口：`https://m.mfuns.net/`。

本机当前无法完成有效的 `m.mfuns.net` 页面加载：域名解析到 `198.18.0.42`（FlClash 虚拟网卡），443 TCP 探测成功，但浏览器与 `curl` 均在 TLS 握手阶段超时；显式使用系统代理 `127.0.0.1:7890` 时亦只完成 CONNECT，随后同样超时。故**尚未提交网页登录表单，也没有获得网页会话的真实接口路径、请求体、Cookie 或令牌**。

### 已验证的 Public API（仅作参考，不接入客户端）

`https://api.mfuns.net/v1/public_api.json` 可正常读取，为 OpenAPI 3.0.3（`Mfuns Public API` 1.0.0）。它与移动站登录体系**严格分离**：除分类接口外，均要求 `Authorization` 请求头中的 `ApiKeyAuth`，不能把网页 Cookie/Token 当作此 API 的 key 使用，反之亦然。该文档仅用于理解投稿字段、分类层级和业务流程；本客户端不调用这些接口，也不收集、保存或要求用户配置 API key。

已成功验证两个无需鉴权的读取接口：

- `GET https://api.mfuns.net/v1/category/video`
- `GET https://api.mfuns.net/v1/category/article`

两者返回统一包装 `{ code, msg, data }`；`data` 是分级分类树，节点含 `id`、`name`、`desc`、`type`、`order`、`public`、`state`、`parent_id` 与可选 `children`。这些字段仅作为数据模型设计参考；客户端的实际分区数据源以移动站抓包结果为准。

OpenAPI 还列出 9 个需 API key 的投稿/媒体接口：视频上传凭证获取与更新、上传完成通知、视频创建与更新、文章创建与更新、我的稿件列表、图片上传。它们不属于本客户端的接入范围；若未来实现投稿，仅以账号密码登录后抓取并验证的网页会话接口为准。

### 第二轮真实会话功能验证（2026-08-10）

以下结论来自 `m.mfuns.net` 的真实浏览器会话。已使用账号密码完成登录，未出现验证码；页面从 `/member/login` 跳转至 `/member`，因此账号密码登录闭环已确认。浏览器本身携带实际 UA，但当前自动化环境不能导出其完整字符串；Flutter 所需的最终 UA 仍应从代理 Network 日志中原样记录后注入。

| 已验证页面 | 实际功能边界 | 客户端优先级 |
| --- | --- | --- |
| `/home` | 推荐流混合视频与文章；11 个顶级分区；热门榜与全站排行入口；搜索与消息入口 | P0 |
| `/member/login` | 单一“用户名/ID/邮箱/手机号”账号字段 + 密码字段；登录后进入个人中心 | P0 |
| `/member` | 资料、经验/喵币、粉丝/关注、历史、账号资料、收藏、签到、媒体库、稿件中心、小黑屋入口 | P0：资料/历史/收藏；其余 P1+ |
| `/search` | 综合、文章、视频、用户四个结果页签；综合结果同时含用户和内容；支持分页加载 | P0 |
| `/timeline` | 时间线/关注双页签，动态卡片含互动与评论入口；存在 `/create/feed` 发布入口 | P1（只读时间线先行） |
| `/video/:id` | 标题、日期、播放/弹幕计数、分区、MV 号、简介、点赞/点踩、分 P、作者关注、标签、相关推荐 | P0；播放地址/清晰度/弹幕协议待抓包 |
| `/member/history` | 文章/视频两页签、历史内容列表和分页 | P0 |

在视频详情当前 DOM 中未发现原生 `<video>` 或 `<iframe>` 节点，故不能据此推断媒体协议；播放器、弹幕和媒体 URL 必须由真实 Network 记录确定。

### 待验证的网页会话 API 候选

站内文章《喵站API接口收集整合》列出了 `api.mfuns.net/v1` 下的推荐、文章/视频详情、评论、搜索相关资源、动态、收藏、分区、榜单、签到、认证与弹幕路径。根据项目要求，其中大部分路径可视为**高可信开发候选**：可先据此建立 API 分组、DTO、Repository 接口和只读页面的实现顺序。

但“高可信路径”不等于可直接写死的完整契约：每个接口仍需在本账号的实际网页会话下确认方法、必需请求头、参数名/类型、鉴权传递、分页游标、错误码和响应字段；认证、互动、评论、签到、投稿等写操作必须先做单独的抓包和回归验收。

本次尝试通过已登录浏览器直接打开 `api.mfuns.net/v1/recommend/get` 时，浏览器客户端报 `ERR_BLOCKED_BY_CLIENT`；自动化工具也不提供 XHR/Fetch 的 Network 请求头读取能力。因此下一步必须在允许记录请求头的代理/DevTools 环境中，以同一账号登录后复现上表页面，再逐个确认：真实路径、方法、必要头字段、请求体、Cookie/Token 传递方式、响应结构和分页语义。

### 社区 API 实施契约

新增的 `mfuns_api_docs.md`（2026-08-02）是本项目的社区 API 主参考，优先于早期站内收集文章。编码前按下列已记录规则实现，并以集成测试验证：

- 登录：`POST /v1/auth/login` 使用 `application/x-www-form-urlencoded` 的 `account`、`password`；响应 `data.access_token` 是唯一会话凭证。
- 鉴权：所有社区请求在 `Authorization` 头直接携带 token，**不加 `Bearer`**；再统一添加默认移动端 Chrome UA（可由构建参数覆盖）。
- 会话：启动时用 `GET /v1/user/info` 且 `code == 1 && data.login == true` 校验；不依赖已记录为 404 的 `/v1/auth/refresh`，token 失效则清除 Secure Storage 并重新登录。
- P0 读取：推荐/分类、文章和视频详情、评论、搜索、用户资料、榜单、分类树、视频播放地址、弹幕读取；按文档的页码或游标字段实现分页。
- 互动与创作：评论、点赞/点踩、收藏、签到、动态、弹幕、投稿均放在后续模块，必须有单独的请求/响应回归测试；不在首次运行中触发写操作。
- 排除项：`mf_` API key 投稿开放平台和 `mfuns.wgen.top` 第三方动态聚合不进入 App 的运行时依赖、配置或请求路径。

不要根据网页路由臆造 API。网络恢复后，按以下顺序建立接口清单：

1. 未登录打开首页、分区、搜索、视频详情，记录 Network 中 JSON/XHR、媒体清单与图片 CDN 请求。
2. 使用授权测试账号登录，记录登录请求、响应、Cookie/Token、刷新与退出行为；不保存密码或完整令牌到仓库/日志。
3. 逐项浏览收藏、历史、评论、关注和个人资料，整理方法、路径、参数、鉴权、分页和错误码。
4. 使用同一会话只读重放请求，定义 DTO 和契约测试样本；写操作仅使用明确的测试数据，并设人工确认。
5. 对播放器单独验证重定向、Referer/Cookie、M3U8/MPD、分片、字幕和清晰度切换。

输出物应为 `docs/api-contract.md`、脱敏的 JSON fixtures 与接口回归测试；不得提交 Cookie、Bearer token、手机号或密码。

## 4. 推荐技术架构

```text
lib/
  app/                 # App、路由、主题、依赖装配
  core/                # Dio、鉴权、错误、日志、缓存、设计令牌
  data/                # API client、DTO、Repository 实现、持久化
  domain/              # 实体、Repository 抽象、Use cases
  features/
    auth/ home/ discover/ search/ video/ player/
    comments/ profile/ favorites/ history/
  shared/              # 可复用组件与工具
```

- 状态管理：Riverpod；路由：go_router；网络：Dio（拦截器处理会话、重试与统一错误）。
- 认证仅保留 `WebSessionApi`：专管由 `m.mfuns.net` 抓包确认的账号密码登录、Cookie/Token 刷新与登出。`api.mfuns.net` 的 API key 体系不进入 App 代码、配置或安全存储。
- 数据模型：Freezed + json_serializable；接口模型与领域模型分离，防止网页接口变动扩散到 UI。
- 本地数据：Drift/SQLite 保存历史、搜索记录和可失效的缓存；敏感会话仅存 Secure Storage。
- 图片：cached_network_image；视频优先使用底层原生播放器能力，针对实际媒体协议选用 `video_player` 及必要扩展。
- 质量：lint、单元/Repository/Widget 测试，接口 fixture 契约测试，GitHub Actions 构建 Android debug APK。

## 5. 关键工程约束

- API 基地址、User-Agent 与日志开关通过 `--dart-define` 注入；开发/预发/生产环境隔离。
- `m.mfuns.net` 的每个网页会话请求必须携带移动端浏览器 UA。默认采用标准 Android Chrome UA：`Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36`。将其放在 `WebSessionApi` 的 Dio 拦截器中统一注入，并允许以 `--dart-define=MFUNS_USER_AGENT=...` 覆盖；禁止在业务页面各自拼接 UA。
- 抓包时同时记录 UA、`Accept`、`Referer`、`Origin`、语言及其他服务端实际校验的头字段；只把确有必要的字段纳入请求策略，并通过脱敏 fixture 回归验证。
- 不在客户端固化账号、密码、私钥或绕过鉴权。401/403 统一触发安全失效和重新登录。
- 网络层仅对幂等 GET 做受限重试；写操作具备幂等键/去重与明确的错误反馈。
- 媒体 URL 默认短期缓存，失效后从详情接口重新获取；播放器错误需要落到可诊断但已脱敏的日志。
- 在获得平台授权前，不实现绕过广告、DRM、签名、访问控制或下载限制的逻辑。

## 6. 实施里程碑

| 阶段 | 交付 | 验收 |
| --- | --- | --- |
| 0. 环境与探测 | Flutter 工程、API 合约、脱敏 fixtures | `flutter doctor` 全绿；核心读取接口可重放 |
| 1. 浏览闭环 | 首页/分区/搜索/详情 | 列表分页、空态、错误态和深链可用 |
| 2. 播放闭环 | 播放器、选集、续播 | 真机播放、切后台恢复、错误恢复通过 |
| 3. 账号闭环 | 登录、会话、收藏、历史、资料 | 会话安全保存；登出清理；接口测试通过 |
| 4. 社区与发布 | 评论/互动及经批准的扩展功能 | 写操作回归测试、风控与审核规则确认 |
| 5. 发布 | 图标、隐私说明、崩溃监控、签名和 CI | Release APK/AAB 可安装、核心路径冒烟通过 |

## 7. 下一步

1. 修复或切换当前 Clash 节点/规则，使 `https://m.mfuns.net/` 能完成 TLS 握手。
2. 将既有 Flutter SDK 加入 PATH，运行 `flutter doctor -v`，再创建项目骨架与 API 35 模拟器。
3. 网络恢复后按第 3 节抓包，冻结 P0 的 `WebSessionApi` 合约；后续投稿也只实现已验证的账号密码网页登录会话接口。
