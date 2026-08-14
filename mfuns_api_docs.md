# Mfuns 公开 API 文档

> 来源：https://open.mfuns.net/api/ （官方文档页）
> 数据源：https://api.mfuns.net/v1/public_api.json （OpenAPI 3.0.3 规范）
> 抓取时间：2026-08-02

## 基本信息

- **接口地址（Base URL）**：`https://api.mfuns.net`
- **OpenAPI 版本**：3.0.3
- **规范版本**：1.0.0

## 鉴权方式

在 `Authorization` 请求头中直接携带 API KEY（`mf_` 开头），**无需** `Bearer` 前缀。

```
Authorization: mf_xxxxxxxxxxxx
```

## 通用响应结构

所有接口返回统一信封结构：

```json
{ "code": 1, "msg": "...", "data": { ... } }
```

`code` 为 `1` 表示成功。

### 错误码

| code | 含义 |
| ---- | ---- |
| 1     | 成功 |
| 0     | 操作失败 |
| 4031  | 缺少参数 |
| 10001 | 参数无效 |
| 401   | API KEY 无效或已过期 |
| 403   | 接口不支持 API KEY 访问，或 IP 不在白名单内 |
| 429   | API KEY 请求频率超限（5 QPS） |
| 500   | 服务器错误 |

### 频率限制

- API KEY 统一限制 **5 QPS**。
- 投稿类接口（create/update）另有**用户级投稿频率限制**（与网页端共享额度）。

---

## 接口总览

| 方法 | 路径 | 分组 | 说明 |
| ---- | ---- | ---- | ---- |
| POST | `/v1/contribute/video/get_upload_auth` | 视频投稿 | 获取视频上传凭证 |
| POST | `/v1/contribute/video/update_upload_auth` | 视频投稿 | 更新视频上传凭证 |
| POST | `/v1/contribute/video/upload_complete` | 视频投稿 | 视频上传完成通知 |
| POST | `/v1/contribute/video/create` | 视频投稿 | 视频投稿 |
| POST | `/v1/contribute/video/update` | 视频投稿 | 更新视频投稿 |
| POST | `/v1/contribute/article/create` | 文章投稿 | 文章投稿 |
| POST | `/v1/contribute/article/update` | 文章投稿 | 更新文章投稿 |
| GET  | `/v1/contribute/list` | 投稿管理 | 获取我的稿件列表 |
| POST | `/v1/media/upload_image` | 素材上传 | 上传图片 |

---

## 投稿状态

`status` 字段在所有稿件相关接口中通用：

| 值 | 含义 |
| -- | ---- |
| 0 | 草稿 |
| 1 | 已发布 |
| 2 | 待审核 |
| 3 | 锁定 |
| 4 | 退回修改 |
| 5 | 定时发布 |

## 版权类型

| 值 | 含义 |
| -- | ---- |
| 0 | 其他 |
| 1 | 转载 |
| 2 | 原创 |

---

## 一、视频投稿

### 1. 获取视频上传凭证

`POST /v1/contribute/video/get_upload_auth`

上传视频前调用，返回阿里云 VOD 上传凭证。

- 支持扩展名：`mp4 / mov / mkv / flv / avi / wmv / webm / mpeg4 / ts / mpg / rm / rmvb / m4v`
- 文件大小受单文件上限与用户当月上传额度限制

**请求体（application/json，必填）：**

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| file_name | string | ✅ | 文件名（含扩展名），如 `video.mp4` |
| file_size | integer | ✅ | 文件大小，单位字节，如 `10485760` |

**示例请求体：**

```json
{
  "file_name": "video.mp4",
  "file_size": 10485760
}
```

**响应 data（阿里云 VOD 上传凭证）：**

| 字段 | 类型 | 说明 |
| ---- | ---- | ---- |
| VideoId | string | 视频 ID，后续接口用 `videoId` 引用 |
| UploadAddress | string | Base64 编码的上传地址 |
| UploadAuth | string | Base64 编码的上传凭证 |
| RequestId | string | 请求 ID |

---

### 2. 更新视频上传凭证

`POST /v1/contribute/video/update_upload_auth`

上传凭证过期后重新获取，仅限尚未完成上传的视频。

**请求体（application/json，必填）：**

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| videoId | string | ✅ | `get_upload_auth` 返回的 VideoId |

**响应 data：** 同"获取视频上传凭证"（阿里云 VOD 上传凭证）。

---

### 3. 视频上传完成通知

`POST /v1/contribute/video/upload_complete`

视频文件上传完成后调用，服务端校验文件大小与时长，校验通过后视频才可用于投稿。

**请求体（application/json，必填）：**

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| videoId | string | ✅ | 上传凭证返回的视频 ID |

**响应 data（视频库记录）：**

| 字段 | 类型 | 说明 |
| ---- | ---- | ---- |
| id | integer | 视频库记录 ID |
| video_id | string | 视频 ID |
| file_name | string | 文件名 |
| file_size | integer | 文件大小（字节） |
| video_duration | integer | 时长（秒） |
| video_width | integer | 宽度 |
| video_height | integer | 高度 |
| status | integer | 0 未上传，1 已上传，2 已使用，3 已删除 |

---

### 4. 视频投稿

`POST /v1/contribute/video/create`

创建视频投稿，投稿进入审核队列。除 API KEY 的 5 QPS 限制外，还受用户投稿频率限制（与网页端共享额度）。

**请求体（application/json，必填）：**

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| cid | integer | ✅ | 分类 ID |
| title | string | ✅ | 标题，最长 30 字 |
| content | string | ✅ | 简介，Quill JSON 富文本，正文不超过 2000 字 |
| video | string | ✅ | 视频列表，JSON 字符串（见下方说明） |
| cover | string | ✅ | 封面，https 图片外链 |
| copyright | integer | ✅ | 版权：0 其他，1 转载，2 原创 |
| tags | string | ❌ | 标签，英文逗号分隔，最多 10 个 |
| series_id | integer | ❌ | 合集 ID |
| publish_at | integer | ❌ | 定时发布时间，秒级 Unix 时间戳 |

**video 字段说明：**

JSON 字符串，元素结构为：

```json
{
  "type": "direct|link",
  "content": "...",
  "title": "..."
}
```

- `type` 为 `direct` 时，`content` 填 `upload_complete` 通过的 videoId
- `type` 为 `link` 时，`content` 填外链地址

**示例请求体：**

```json
{
  "cid": 1,
  "title": "我的视频",
  "content": "{\"ops\":[{\"insert\":\"简介内容\\n\"}]}",
  "video": "[{\"type\":\"direct\",\"content\":\"b1c2d3e4...\",\"title\":\"P1\"}]",
  "cover": "https://example.com/cover.jpg",
  "copyright": 2,
  "tags": "科技,数码"
}
```

**响应 data（ContributeResult）：**

| 字段 | 类型 | 说明 |
| ---- | ---- | ---- |
| contribute.id | integer | 投稿 ID |
| contribute.user_id | integer | 用户 ID |
| contribute.resource_type | integer | 资源类型 |
| contribute.resource_id | integer | 审核发布后关联的资源 ID，未发布时为 0 |
| contribute.resource_data | object | 投稿内容快照（标题、正文、封面、视频列表等） |
| contribute.status | integer | 投稿状态（见通用状态表） |
| contribute.publish_at | string \| null | 定时发布时间 |
| contribute.created_at | string | 创建时间 |
| contribute.updated_at | string | 更新时间 |

---

### 5. 更新视频投稿

`POST /v1/contribute/video/update`

更新已创建的视频投稿，仅限本人投稿，投稿须未被锁定。更新后投稿重新进入审核队列。与 create 共享用户投稿频率限制。

**请求体（application/json，必填）：**

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| contribute_id | integer | ✅ | 投稿 ID（create 返回） |
| cid | integer | ✅ | 分类 ID |
| title | string | ✅ | 标题，最长 50 字 |
| content | string | ✅ | 简介，Quill JSON 富文本，正文不超过 2000 字 |
| video | string | ✅ | 视频列表，JSON 字符串（同 create） |
| cover | string | ✅ | 封面，https 图片外链 |
| copyright | integer | ✅ | 版权：0 其他，1 转载，2 原创 |
| tags | string | ❌ | 标签，英文逗号分隔，最多 10 个 |
| series_id | integer | ❌ | 合集 ID |
| publish_at | integer | ❌ | 定时发布时间，秒级 Unix 时间戳 |

**响应 data：** 同"视频投稿"（ContributeResult）。

---

## 二、文章投稿

### 6. 文章投稿

`POST /v1/contribute/article/create`

创建文章投稿，支持 Quill JSON 或 Markdown 正文。除 API KEY 的 5 QPS 限制外，还受用户投稿频率限制（与网页端共享额度）。

**请求体（application/json，必填）：**

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| cid | integer | ✅ | 分类 ID |
| title | string | ✅ | 标题，最长 30 字 |
| content | string | ✅ | 正文，格式由 content_format 决定 |
| copyright | integer | ✅ | 版权：0 其他，1 转载，2 原创 |
| content_format | string | ❌ | 正文格式：`quill` / `markdown`，默认 `quill`。markdown 会由服务端转换为 Quill JSON |
| tags | string | ❌ | 标签，英文逗号分隔，最多 10 个 |
| cover | string | ❌ | 封面，https 图片外链 |
| series_id | integer | ❌ | 合集 ID |
| publish_at | integer | ❌ | 定时发布时间，秒级 Unix 时间戳 |
| draft | boolean | ❌ | 是否存为草稿，默认 `false`。草稿模式跳过参数验证 |

**示例请求体（Markdown 正文）：**

```json
{
  "cid": 1,
  "title": "我的文章",
  "content": "# 标题\n\n正文内容",
  "content_format": "markdown",
  "copyright": 2,
  "draft": false
}
```

**响应 data：** ContributeResult（同"视频投稿"）。

---

### 7. 更新文章投稿

`POST /v1/contribute/article/update`

更新已创建的文章投稿，仅限本人投稿，投稿须未被锁定。更新后投稿重新进入审核队列。与 create 共享用户投稿频率限制。

**请求体（application/json，必填）：**

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| contribute_id | integer | ✅ | 投稿 ID（create 返回） |
| cid | integer | ✅ | 分类 ID |
| title | string | ✅ | 标题，最长 50 字 |
| content | string | ✅ | 正文，格式由 content_format 决定 |
| copyright | integer | ✅ | 版权：0 其他，1 转载，2 原创 |
| content_format | string | ❌ | 正文格式：`quill` / `markdown`，默认 `quill` |
| tags | string | ❌ | 标签，英文逗号分隔，最多 10 个 |
| cover | string | ❌ | 封面，https 图片外链 |
| series_id | integer | ❌ | 合集 ID |
| publish_at | integer | ❌ | 定时发布时间，秒级 Unix 时间戳 |
| draft | boolean | ❌ | 是否存为草稿，默认 `false` |

**响应 data：** ContributeResult（同"视频投稿"）。

---

## 三、投稿管理

### 8. 获取我的稿件列表

`GET /v1/contribute/list`

获取当前 API KEY 所属用户的投稿列表。`type` 为 0 时返回文章，1 时返回视频。可按投稿状态过滤。

**Query 参数：**

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| type | integer | ✅ | 稿件类型：0 文章，1 视频 |
| page | integer | ❌ | 页码，从 1 开始，默认 1 |
| size | integer | ❌ | 每页数量，默认 20，最大 100 |
| status | integer | ❌ | 投稿状态（见通用状态表），不传返回全部 |

**响应 data：**

| 字段 | 类型 | 说明 |
| ---- | ---- | ---- |
| list | array | 稿件列表（ContributeListItem） |
| total | integer | 稿件总数 |

**ContributeListItem 字段：**

| 字段 | 类型 | 说明 |
| ---- | ---- | ---- |
| id | integer | 投稿 ID |
| resource_id | integer | 审核发布后关联的资源 ID，未发布时为 0 |
| title | string | 标题 |
| cover | string | 封面 |
| tags | array\<string\> | 标签数组 |
| type | integer | 0 文章，1 视频 |
| status | integer | 投稿状态（见通用状态表） |
| created_at | integer | 创建时间，秒级时间戳 |
| published_at | integer \| null | 资源发布时间，秒级时间戳 |
| scheduled_publish_at | integer \| null | 定时发布时间，秒级时间戳 |
| series_id | integer \| null | 合集 ID |
| series_title | string \| null | 合集标题 |
| resource | object \| null | 已发布资源的详情，未发布为 null |

---

## 四、素材上传

### 9. 上传图片

`POST /v1/media/upload_image`

上传图片到个人媒体库。

- 支持格式：`jpg / jpeg / png / gif / webp / bmp / svg`

**请求体（multipart/form-data，必填）：**

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| file | binary | ✅ | 图片文件 |

**响应 data：**

| 字段 | 类型 | 说明 |
| ---- | ---- | ---- |
| file.id | integer | 媒体文件 ID |
| file.user_id | integer | 用户 ID |
| file.file_name | string | 文件名 |
| file.file_path | string | 图片路径，可通过 `/v1/file/image?path=` 访问 |
| file.width | integer | 宽度 |
| file.height | integer | 高度 |
| file.blurhash | string | BlurHash 占位图 |
| file.file_sha1 | string | 文件 SHA1 |
| file.file_type | integer | 文件类型 |
| file.storage_type | string | 存储类型 |

---

## 错误响应

所有接口共用以下错误响应：

**401 API KEY 无效或已过期：**

```json
{ "code": 401, "msg": "API KEY 无效或已过期" }
```

**403 接口不支持 API KEY 访问，或 IP 不在白名单内：**

```json
{ "code": 403, "msg": "IP 不在白名单内" }
```

**429 请求频率超限（API KEY 限制 5 QPS；投稿接口另有用户级投稿频率限制）：**

```json
{ "code": 429, "msg": "API KEY 请求频率超限" }
```

---

# 社区 API 补充（抓包 + 实测验证）

> 以下接口为喵御宅社区站（www.mfuns.net / m.mfuns.net）实际使用的接口，作为官方开放平台文档的补充。
> 来源：前端 Nuxt 打包产物逆向 + 使用用户 token 实测（测试帖：https://m.mfuns.net/article/83888，用户 17627）。
> 验证时间：2026-08-02。所有标注 ✅ 的接口均已实测通过；⚠️ 表示接口存在但参数受限或需注意。

## 鉴权

通过账密登录 token（`/v1/auth/login` 返回的 `access_token`），放在 `Authorization` 请求头，无 Bearer 前缀：

```
Authorization: YWRUeHBCVkNYd3pqJmlkJjE3NjI3...
```

## 请求格式

- GET 接口：query 参数
- POST 接口：**JSON body 与表单（form-urlencoded）均可**（实测两者都返回成功）
- 通用响应信封：`{"code": 1, "msg": "...", "data": {...}}`，`code == 1` 成功
- 内容类字段（正文/评论）为 **Quill JSON 字符串**；请求带 `html=1` 时服务端返回渲染后的 HTML

## 资源类型（type）对照

> **修正（2026-08-02 实测）**：评论点赞实际为 **type=4**（与动态同类型），文档原标注的 3 已废弃——前端抓包 `/v1/like/like {"id":1208342,"type":4}` 实证，且 type=3 对评论返回 404「资源不存在」。

| 场景 | 文章 | 视频 | 评论 | 动态 |
| ---- | ---- | ---- | ---- | ---- |
| 点赞（like/status） | 0 ✅ | 1 ✅ | 4 ✅ | 4 |
| 收藏（favorite） | 0 ✅ | 1 | - | - |

---

## 接口总览（按优先级）

| 优先级 | 功能 | 方法 | 路径 | 状态 |
| ------ | ---- | ---- | ---- | ---- |
| P0 | 帖子列表（首页推荐流） | GET | `/v1/recommend/get` | ✅ |
| P0 | 帖子列表（分类） | GET | `/v1/category/list` | ✅ |
| P0 | 帖子列表（用户） | GET | `/v1/article/user_list` | ✅ |
| P0 | 帖子详情 | GET | `/v1/article/get` | ✅ |
| P0 | 评论列表 | GET | `/v1/comment/list` | ✅ |
| P0 | 评论区信息 | GET | `/v1/comment/area_info` | ✅ |
| P0 | 评论回复列表 | GET | `/v1/comment/reply_list` | ✅ |
| P0 | 发表评论 | POST | `/v1/comment/create` | ✅ |
| P0 | 回复评论 | POST | `/v1/comment/create_reply` | ✅ |
| P0 | 删除评论 | POST | `/v1/comment/delete` | ✅ |
| P0 | 创建帖子 | POST | `/v1/contribute/article/create` | ✅（即开放平台"文章投稿"，见上文第五节） |
| P1 | 用户详情 | GET | `/v1/user/get_user` | ✅ |
| P1 | 当前用户 | GET | `/v1/user/info` | ✅ |
| P1 | 点赞 | POST | `/v1/like/like` | ✅ |
| P1 | 取消点赞 | POST | `/v1/like/cancel` | ✅ |
| P1 | 点踩 | POST | `/v1/like/dislike` | ✅ |
| P1 | 点赞状态 | GET | `/v1/like/status` | ✅ |
| P1 | 搜索内容 | GET | `/v1/search/resource` | ✅ |
| P1 | 搜索用户 | GET | `/v1/search/user` | ✅ |
| P1 | 热门榜 | GET | `/v1/leaderboards/hot` | ✅ |
| P1 | 站内热门 | GET | `/v1/leaderboards/site` | ✅ |
| P1 | 分类树 | GET | `/v1/category/all` | ✅ |
| P1 | 分类详情 | GET | `/v1/category/get` | ✅ |
| P2 | 通知计数 | GET | `/v1/notify/count` | ✅ |
| P2 | 通知列表 | GET | `/v1/notify/get` | ✅ |
| P2 | 站内通知 | GET | `/v1/notify/site` | ✅ |
| P2 | 浏览历史 | GET | `/v1/history/get` | ✅ |
| P2 | 清除历史 | GET | `/v1/history/clean` | ⚠️ 前端调用，未实测（破坏性） |
| P2 | 我的收藏夹列表 | GET | `/v1/favorite/get_favorite_list` | ✅ |
| P2 | 收藏夹内容 | GET | `/v1/favorite/get_favorite_item` | ✅ |
| P2 | 收藏夹详情 | GET | `/v1/favorite/get_favorite_info` | ✅ |
| P2 | 是否已收藏 | GET | `/v1/favorite/is_favorite` | ✅ |
| P2 | 创建收藏夹 | POST | `/v1/favorite/create_favorite_list` | ✅ |
| P2 | 修改收藏夹 | POST | `/v1/favorite/update_favorite_list` | ⚠️ 前端调用，未实测 |
| P2 | 删除收藏夹 | POST | `/v1/favorite/delete_favorite_list` | ✅ |
| P2 | 添加收藏 | POST | `/v1/favorite/add_favorite` | ✅ |
| P2 | 移除收藏（条目） | POST | `/v1/favorite/remove_favorite` | ⚠️ 前端调用，未实测 |
| P2 | 移除收藏（资源） | POST | `/v1/favorite/remove_favorite_by_resource` | ✅ |
| P2 | 动态流（第三方聚合，LLM 友好） | GET | `https://mfuns.wgen.top/llm/latest` | ✅ 第三方服务 |
| P2 | 动态流（第三方原始时间线） | GET | `https://mfuns.wgen.top/latest` | ✅ 第三方服务 |
| P2 | 动态流抓取统计 | GET | `https://mfuns.wgen.top/stats` | ✅ 第三方服务 |
| P2 | 全站动态列表（官方） | GET | `/v1/feeds/list` | ✅ |

> 注：动态流（feed）由第三方聚合服务 `mfuns.wgen.top` 提供（详见文末"第三方动态流聚合 API"章节）；官方 `/v1/feeds/list` 为全站动态接口（`start_id` 游标分页）。

---

## P0 帖子

### 帖子列表

前端 store 中的 `/v1/article/list` 在服务端已不存在（返回 404，属前端遗留代码），帖子列表实际使用以下三个接口：

**1. 首页推荐流：`GET /v1/recommend/get`** ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| category | integer | ❌ | 分类 ID，默认 -1（全部） |
| size | integer | ❌ | 数量，默认 20 |

**2. 分类帖子列表：`GET /v1/category/list`** ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| cid | integer | ✅ | 分类 ID（如 51=交友专区，49=站内互动） |
| page | integer | ❌ | 页码，默认 1 |
| size | integer | ❌ | 每页数量，默认 20 |

响应 `data`：`{list: [...], total: n}`，每条含 `id / title / summary / cover / cover_meta / tag / user / like_count / view_count / comment_count` 等。

**3. 用户帖子列表：`GET /v1/article/user_list`** ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| user_id | integer | ✅ | 用户 ID |
| aid | integer | ❌ | 游标，0 为第一页 |
| type | string | ❌ | 过滤，默认 `pass` |

响应 `data`：文章数组。

### 帖子详情

**`GET /v1/article/get`** ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| id | integer | ✅ | 文章 ID（URL 中的数字，如 83888） |
| html | integer | ❌ | 1 = 返回渲染后的 HTML |
| exposure_id / source | string | ❌ | 曝光统计参数，可选 |

响应 `data`：`{article: {id, user_id, title, content, content_type, cover, status, comment_area_id, created_at, ...}, tags, likeCount, like_status, commentId, viewCount, category, favorite_count, reward_count, floor_num}`。

- `comment_area_id`：该帖的评论区 ID，评论列表接口用
- `content_type`：2 = markdown 渲染（1 = Quill 富文本）

### 创建帖子

即开放平台的 **`POST /v1/contribute/article/create`**（见本文档"文章投稿"一节），社区前端调用参数完全相同（`title, content, cid, tags, cover, copyright, draft`），可用 `draft: true` 存草稿、`/v1/contribute/article/delete` 删除。实测：✅ 创建草稿（id 185291）→ 删除成功。

---

## P0 评论

### 评论区信息：`GET /v1/comment/area_info` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| area_id | integer | ✅ | 评论区 ID（帖子详情返回的 comment_area_id） |

响应 `data`：`{id, resource_id, resource_type, floor_num, floor_count, pin_floor_id, page_count, has_hot_comments}`。

### 评论列表：`GET /v1/comment/list` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| area_id | integer | ✅ | 评论区 ID |
| page | integer | ❌ | 页码，默认 1 |
| order | string | ❌ | `asc` / `desc`，默认 desc |
| html | integer | ❌ | 1 = 返回 HTML |

响应 `data`：评论数组，每条含 `id / comment_area_id / user_id / floor_num / content / content_type / content_ext(images) / like_count / reply_count / is_second_reply / is_delete / created_at`。

### 评论回复列表：`GET /v1/comment/reply_list` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| comment_id | integer | ✅ | 一级评论 ID |
| page | integer | ❌ | 页码，默认 1 |
| html | integer | ❌ | 1 = 返回 HTML |

### 发表评论：`POST /v1/comment/create` ✅

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| area_id | integer | ✅ | 评论区 ID |
| content | string | ✅ | 评论内容，Quill JSON 字符串 |
| images | string | ❌ | 图片列表 JSON 字符串，如 `["url1","url2"]` |
| html | integer | ❌ | 1 = 返回 HTML |

示例：

```json
{
  "area_id": 146979,
  "content": "{\"ops\":[{\"insert\":\"评论内容\\n\"}]}",
  "images": "[]",
  "html": 1
}
```

实测：✅ 发布成功（返回 `{comment_area_id, floor_num, content, ...}`）→ 删除成功。

### 回复评论：`POST /v1/comment/create_reply` ✅

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| comment_id | integer | ✅ | 被回复的评论 ID |
| content | string | ✅ | 回复内容，Quill JSON 字符串 |

实测：✅ 回复成功。

### 删除评论：`POST /v1/comment/delete` ✅

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| comment_id | integer | ✅ | 评论 ID（注意不是 id） |

实测：✅ 删除成功（帖子评论区恢复原状）。

---

## P1 用户

### 当前用户：`GET /v1/user/info` ✅（无需参数）

响应 `data`：`{login: true, user: {id, name, avatar, bio, gender, badges, level_id, created_at, ...}}`。未登录时 `login: false`。

### 用户详情：`GET /v1/user/get_user` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| id | integer | ✅ | 用户 ID（如 17627） |

响应 `data`：用户资料（`name / avatar / avatar_frame / badges / info / fans / level_id / gender / bio` 等）。

### 其他用户接口（前端已确认存在）

| 接口 | 说明 |
| ---- | ---- |
| `GET /v1/user/badge_all` | 全部徽章列表（sign.py 中用于查询等级名称） |
| `GET /v1/user/user_badges` | 用户徽章 |
| `GET /v1/user/level_section` | 等级区间 |
| `GET /v1/user/set_name / set_avatar / set_bio / set_gender / set_badge / set_banner_image` | 资料修改（POST） |
| `GET /v1/user/get_user` 参数 `user_id` 不可用，必须用 `id`（实测 user_id 返回"获取失败"） |

---

## P1 点赞

### 点赞 / 点踩 / 取消：`POST /v1/like/like`、`/v1/like/dislike`、`/v1/like/cancel` ✅

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| id | integer | ✅ | 资源 ID |
| type | integer | ✅ | 资源类型：0 文章，1 视频，4 评论/动态（实测评论为 4，文档早期标注的 3 已废弃） |

### 点赞状态：`GET /v1/like/status` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| id | integer | ✅ | 资源 ID |
| type | integer | ✅ | 资源类型（同上） |

响应 `data`：`{status: {like: {count, is_active}, dislike: {count, is_active}}}`。

实测：✅ `like/like`（type=0）→ 返回成功 → `like/cancel` 成功，点赞数不变。

---

## P1 搜索

### 搜索内容：`GET /v1/search/resource` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| text | string | ✅ | 搜索关键词 |
| type | integer | ✅ | -1 全部，0 文章，1 视频 |
| page | integer | ❌ | 页码，默认 1 |
| size | integer | ❌ | 每页数量 |
| sort | string | ❌ | 排序，默认 `all`（如 `time`） |

响应 `data`：`{list: [{id, title, summary, cover, tag, user, ...}]}`，含 `total`。

### 搜索用户：`GET /v1/search/user` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| user | string | ✅ | 关键词 |
| page | integer | ❌ | 页码 |
| size | integer | ❌ | 每页数量，默认 20 |

响应 `data`：`{total, list: [{id, name, avatar, avatar_frame, badges, info, fans, highlight}]}`。

---

## P1 热门 / 分类

### 热门榜：`GET /v1/leaderboards/hot` ✅（无参数）

响应 `data`：热门内容数组（`id / title / summary / cover / tag / user`）。

### 站内热门：`GET /v1/leaderboards/site` ✅（无参数）

### 分类树：`GET /v1/category/all` ✅（无参数）

响应 `data`：完整分类树（`id / name / desc / type / order / parent_id / children[]`）。

### 分类筛选：`GET /v1/category/article` / `/v1/category/video` ✅（无参数）

分别返回文章/视频分类列表。

### 分类详情：`GET /v1/category/get` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| id | integer | ✅ | 分类 ID |

---

## P2 通知

### 通知计数：`GET /v1/notify/count` ✅（无参数）

响应 `data`：`{mention, comment, like, system, message}` 各类型未读数。

### 通知列表：`GET /v1/notify/get` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| type | integer | ✅ | 1 收到的赞，2 收到的评论/回复，3 @提及 |
| page | integer | ❌ | 页码 |

响应 `data`：通知数组，`notify_type` 与请求 type 对应，`notify_params` 携带 `text / comment_id / reply_text` 等详情，`sender_user_id` 为触发者。

### 站内公告：`GET /v1/notify/site` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| page | integer | ❌ | 页码 |
| html | integer | ❌ | 1 = 返回 HTML |

> 注意：前端 `/message/comment`、`/message/like`、`/message/notify` 只是**页面路由**，没有对应独立 API，消息中心实际就是调用 `/notify/get` 按 type 过滤。

---

## P2 互动历史

### 浏览历史：`GET /v1/history/get` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| resource_type | integer | ❌ | 资源类型过滤（0 文章 / 1 视频），不传返回全部 |
| start_time | integer | ❌ | 起始时间游标（秒级时间戳） |

响应 `data`：历史数组，每条 `{id, resource_info: {id, title, summary, cover, tag, user}}`（浏览过的资源）。

### 清除历史：`GET /v1/history/clean` ⚠️（前端调用，破坏性，未实测）

> 注：互动消息（收到的赞/评论）通过 `/v1/notify/get` 的 type=1/2 获取，见上文"通知"。

---

## P2 收藏

### 我的收藏夹列表：`GET /v1/favorite/get_favorite_list` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| user_id | integer | ✅ | 用户 ID |
| resource_id | integer | ❌ | 可选 |
| resource_type | integer | ❌ | 可选 |

响应 `data`：`{list: [{id, user_id, name, desc, status, created_at, count}]}`（含默认收藏夹）。

### 收藏夹内容：`GET /v1/favorite/get_favorite_item` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| favorite_id | integer | ✅ | 收藏夹 ID |
| last_id | integer | ❌ | 游标，0 为第一页 |

### 收藏夹详情：`GET /v1/favorite/get_favorite_info` ✅（参数 favorite_id）

### 是否已收藏：`GET /v1/favorite/is_favorite` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| resource_id | integer | ✅ | 资源 ID |
| resource_type | integer | ✅ | 0 文章，1 视频 |

响应 `data`：`{is_favorite: bool, count: n}`。

### 创建收藏夹：`POST /v1/favorite/create_favorite_list` ✅

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| name | string | ✅ | 收藏夹名称 |
| desc | string | ❌ | 描述 |
| status | integer | ✅ | 可见性，**最小值为 1**（0 会报 10001 参数无效） |

> 响应 `data` 为空数组，**不返回新收藏夹 ID**，需再调用 `get_favorite_list` 查询获取。

### 修改收藏夹：`POST /v1/favorite/update_favorite_list` ⚠️

字段：`id, name, desc, status`。

### 删除收藏夹：`POST /v1/favorite/delete_favorite_list` ✅

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| id | integer | ✅ | 收藏夹 ID |

### 添加收藏：`POST /v1/favorite/add_favorite` ✅

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| list_id | integer | ✅ | 收藏夹 ID |
| resource_id | integer | ✅ | 资源 ID |
| type | integer | ✅ | 资源类型：0 文章，1 视频 |

实测：✅ 添加到收藏夹 → `is_favorite` 返回 `{is_favorite: true, count: 1}` → `get_favorite_item` 可查到资源。

### 移除收藏（按条目）：`POST /v1/favorite/remove_favorite` ⚠️（字段 item_id）

### 移除收藏（按资源）：`POST /v1/favorite/remove_favorite_by_resource` ✅

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| resource_id | integer | ✅ | 资源 ID |
| list_id | integer | ✅ | 收藏夹 ID |
| type | integer | ✅ | 资源类型 |

### 收藏夹订阅：`POST /v1/favorite/subscribe_favorite` / `unsubscribe_favorite`（字段 id）、`GET /v1/favorite/get_subscription_list` ✅（返回 `{list: []}`）

---

## 其他有用接口（顺带确认）

| 接口 | 说明 | 状态 |
| ---- | ---- | ---- |
| `GET /v1/tag/article_list` | 标签下文章列表（参数 `tag, page`） | ✅ |
| `GET /v1/tag/feed_list` / `tag/search` | 标签动态/搜索 | 前端调用，未实测 |
| `GET /v1/feeds/list` | 动态列表（参数 `start_id, html`；可加 `user_id, follow`） | ✅ |
| `GET /v1/feeds/user` | 关注的用户列表 | ✅ |
| `GET /v1/feeds/get` | 动态详情（参数 `id, html`） | 前端调用，未实测 |
| `POST /v1/feeds/create` / `forward` / `delete` | 动态发布/转发/删除 | 前端调用，未实测 |
| `GET /v1/contribute/get` | 投稿详情（参数 `contribute_id`） | ✅（存在，无此投稿时返回 10001） |
| `POST /v1/contribute/article/delete` | 删除投稿（参数 `contribute_id`） | ✅ |
| `GET /v1/recommend/related` | 相关推荐（`resource_id, resource_type, type, size`） | ✅ |
| `GET /v1/message/list` / `send` / `record` | 私信列表/发送/记录 | ✅（list 实测可用） |
| `POST /v1/auth/login` | 登录（`account, password` 表单），返回 `access_token` | ✅（详见下方"登录与 Token"章节） |

---

# 登录与 Token 获取

> 所有社区接口与工具（sign.py / danmu.py / coin.py / 外链工具）的鉴权都基于这套流程。实测时间：2026-08-02。

## 登录：`POST /v1/auth/login` ✅

- 请求体：**表单编码**（`Content-Type: application/x-www-form-urlencoded`），不是 JSON
- 响应 `data.access_token` 即后续所有请求的凭证

```bash
curl -X POST https://api.mfuns.net/v1/auth/login \
  -d "account=手机号或用户名" -d "password=密码"
```

```json
{ "code": 1, "msg": "okey dokey", "data": { "access_token": "YWRUeHBCVkNYd3pqJmlkJjE3NjI3..." } }
```

## Token 使用

- 所有接口在 `Authorization` 请求头中**直接携带 token**，无 Bearer 前缀
- token 为 Base64 编码，解码后包含用户 ID：`adTxpBVCXwzj&id&17627&1ee23284...`（`id&` 后为用户 ID），可用于本地快速确认归属用户
- 建议本地持久化（sign.py 等工具存 `token.pkl`），避免频繁登录

## Token 有效期与刷新

- **有效期约 25 天**：实测 `/v1/auth/get_active_login_session` 返回的 `expire_time` 与签发时间差 ≈ 24~25 天
- `POST /v1/auth/refresh`：前端代码存在调用，但**服务端实测返回 404**（与 `/article/list` 同属前端遗留代码），**不能依赖刷新续期**，过期后只能重新登录
- 登录后可用 `GET /v1/auth/get_active_login_session` 查看当前设备会话（`session_id / expire_time / active_ip / login_time`），`POST /v1/auth/delete_login_session`（`session_id`）可主动踢下线

## Token 有效性校验（重要修正）

sign.py / danmu.py / coin.py 中用的校验接口是 `GET /v1/user/profile`，**该接口实际返回 404**（HTTP 200 + `{"code":404,"msg":"Http Error: Not Found"}`），而脚本的 `isTokenValid` 只判断 HTTP 200，导致**校验永远通过、token 失效也发现不了**。

正确的校验方式：

| 接口 | 判断条件 |
| ---- | ---- |
| `GET /v1/user/info` ✅ | HTTP 200 且 `code == 1` 且 `data.login == true`（未登录返回 `login: false`） |

```python
def is_token_valid(token):
    r = requests.get("https://api.mfuns.net/v1/user/info",
                     headers={"Authorization": token})
    body = r.json()
    return r.status_code == 200 and body.get("code") == 1 and body.get("data", {}).get("login") is True
```

## 其他 auth 接口（前端已确认存在）

| 接口 | 说明 | 状态 |
| ---- | ---- | ---- |
| `POST /v1/auth/register` | 注册（`name, password, phone, code`） | 前端调用，未实测 |
| `POST /v1/auth/logout` | 退出登录 | 前端调用，未实测 |
| `POST /v1/auth/send_sms_code` | 发送短信验证码（`phone`） | 前端调用，未实测 |
| `POST /v1/auth/send_email_code` | 发送邮箱验证码（`email`） | 前端调用，未实测 |
| `GET /v1/auth/user_security_info` | 账号安全信息（邮箱/手机号脱敏） | ✅ |
| `POST /v1/auth/update_password` | 修改密码（`old_password, password`） | 前端调用，未实测 |
| `POST /v1/auth/reset_password` | 重置密码（`phone, phone_code, password`） | 前端调用，未实测 |
| `POST /v1/auth/update_phone` / `update_email` | 换绑手机/邮箱 | 前端调用，未实测 |
| `POST /v1/auth/bind_phone` / `bind_email` | 绑定手机/邮箱 | 前端调用，未实测 |
| `POST /v1/auth/delete_login_session` | 删除登录会话（`session_id`） | 前端调用，未实测 |

---

# 弹幕与视频接口补充（danmu.py + 外链投稿工具）

> 来源：本地工具 `danmu.py`（B站弹幕搬运）、`mfuns外链复活工具.py`（外链视频投稿）+ 前端包逆向 + 实测。
> 验证时间：2026-08-02。测试视频：账号本人的视频 59514，发送测试弹幕 1 条（`get_normal` 已确认落库，弹幕 ID 106048）。

## 弹幕接口

### 发送普通弹幕：`POST /v1/danmaku/send_normal` ✅

danmu.py 使用的接口。请求体（JSON）：

| 字段 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| video_id | integer | ✅ | 目标视频 ID |
| part | integer | ❌ | 分 P 序号，默认 1 |
| time | number | ✅ | 弹幕出现时间（秒，支持小数） |
| content | string | ✅ | 弹幕文本 |
| color | integer | ✅ | 颜色 RGB 十进制整数（如白色 16777215 = 0xFFFFFF） |
| size | integer | ✅ | 字号（工具默认 25） |
| type | integer | ✅ | 弹幕类型：1 滚动，4 底部，5 顶部（与 B 站 XML 的 p 属性第二位一致） |

示例：

```json
{
  "video_id": 59514,
  "part": 1,
  "time": 12.5,
  "content": "测试弹幕",
  "color": 16777215,
  "size": 25,
  "type": 1
}
```

实测：✅ 发送成功（`code=1`），立即通过 `get_normal` 拉取可见。

> 注意：**没有弹幕删除接口**，弹幕一旦发出无法撤回；且服务端对 `video_id` 存在性校验宽松（不存在的视频 ID 也返回成功），发送前请自行确认视频 ID 有效。

### 获取弹幕列表：`GET /v1/danmaku/get_normal` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| id | integer | ✅ | 视频 ID（缺省返回 4031 参数错误） |
| part | integer | ❌ | 分 P 序号 |

响应 `data`：`{list: [...]}`，每条为数组 `[time, type, color, user_id, content, size, created_at, danmaku_id]`：

```json
{
  "list": [
    [1, 1, 16777215, 17627, "API文档验证-可忽略", 25, 1785606761, 106048]
  ]
}
```

| 下标 | 含义 |
| ---- | ---- |
| 0 | time 弹幕时间（秒） |
| 1 | type 弹幕类型（1 滚动 / 4 底部 / 5 顶部） |
| 2 | color 颜色 RGB 十进制 |
| 3 | user_id 发送者用户 ID |
| 4 | content 弹幕文本 |
| 5 | size 字号 |
| 6 | created_at 发送时间（秒级时间戳） |
| 7 | danmaku_id 弹幕 ID |

（DPlayer 风格弹幕 API，播放器直接把 `{baseUrl}/danmaku/get_normal` 配为 api、`id` 传视频 ID。）

---

## 视频接口

### 视频详情：`GET /v1/video/get` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| id | integer | ✅ | 视频 ID |
| html | integer | ❌ | 1 = 返回渲染后的 HTML |
| noAddress | integer | ❌ | 1 = 不返回播放地址 |
| exposure_id / source | string | ❌ | 曝光统计参数，可选 |

响应 `data`：`{id, user_id, title, copyright, videos: [{title, width, height, isPortrait, is2K, is4K}], content, cover, comment_area_id, danmaku_area_id, view_count, like_status, category, ...}`。

> 注意：视频不存在时返回 HTTP 200 + `{"code": 404, "msg": "视频不存在"}`，不是 HTTP 404。

### 获取播放地址：`GET /v1/video/getPlayAddress` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| id | integer | ✅ | 视频 ID |

响应 `data`：`{videos: [{video_url: [{name: "360P", label: "流畅", url, format: "mp4", fps, size, duration}, ...]}]}`。

- URL 为阿里云 VOD 签名直链（带 `auth_key` 时效参数），360P 流畅 / 540P 标清 / 720P 高清等多清晰度
- 此接口**无需登录**即可调用（实测未带 token 也能取到地址，直播流/防盗链策略以实际为准）

### 用户视频列表：`GET /v1/video/user_list` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| user_id | integer | ✅ | 用户 ID |
| vid | integer | ❌ | 游标，0 为第一页 |
| type | string | ❌ | 过滤，默认 `pass` |

> 与文章一致，前端遗留的 `/v1/video/list` 已不存在（404），视频列表请用 `user_list`、分类列表 `/v1/category/list`、推荐流 `/v1/recommend/get`、搜索 `/v1/search/resource`（type=1）。

---

## 外链视频投稿（外链复活工具）

`mfuns外链复活工具.py` 实际就是开放平台的 **`POST /v1/contribute/video/create`**（见本文档"视频投稿"一节），关键点是 **`video` 字段里 `type: "link"`**：

```json
{
  "cid": 46,
  "title": "视频标题",
  "content": "{\"ops\":[{\"insert\":\"简介\\n\"}]}",
  "tags": "标签1,标签2",
  "cover": "/static/xxx.png 或 https 外链",
  "video": "[{\"title\":\"视频标题\",\"type\":\"link\",\"content\":\"https://example.com/video.mp4 直链地址\"}]",
  "copyright": 0
}
```

- `video` 数组元素：`type` 为 `link` 时，`content` 填**视频直链 URL**（复活失效的 B 站等外链视频）
- `copyright` 为 0（其他）适合转载场景
- 实测该工具用的 `Content-Type: application/json` + JSON body 投稿成功（与社区接口可用表单不同，投稿接口要求 JSON 格式）

## 弹幕类型对照（B 站 XML → mfuns）

danmu.py 的解析映射：B 站 XML `p` 属性第 2 位（type）与 ASS Style（top/bottom 定位）最终映射到 mfuns：

| type 值 | 含义 |
| ------- | ---- |
| 1 | 滚动弹幕（默认，ASS 普通样式） |
| 4 | 底部弹幕（ASS Style 含 bottom） |
| 5 | 顶部弹幕（ASS Style 含 top） |

---

# 第三方动态流聚合 API（mfuns.wgen.top）

> **非官方接口**。由第三方自建服务"本地内容聚合服务"提供，持续抓取喵御宅的**动态（feed）/ 视频（video）/ 文章（article）**内容并提供统一时间线接口。用户动态流即由此实现。
> 服务类型：FastAPI（自带 `/docs` Swagger UI、`/openapi.json` 完整规范）。验证时间：2026-08-02。
> 典型用途：AstrBot 等 LLM 机器人插件（`D:\Codes\mfuns-latest\plug\main.py`）通过它回答"MFuns 最近有什么更新"。

## Base URL

```
https://mfuns.wgen.top
```

## 接口总览

| 方法 | 路径 | 说明 |
| ---- | ---- | ---- |
| GET | `/llm/latest` | LLM/AI Agent 友好的最新内容接口（支持 markdown/json 输出） |
| GET | `/latest` | 原始时间线接口（JSON 数组） |
| GET | `/stats` | 已抓取内容统计（feed/video/article 数量） |
| GET | `/webui/`、`/` | 网页版查看界面 |
| GET | `/docs`、`/redoc`、`/openapi.json` | 接口文档 |

## 1. LLM 友好接口：`GET /llm/latest` ✅

默认使用的接口（`mfuns.wgen.top/llm/latest`）。

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| type | string | ❌ | `all`（默认）/ `feed` / `video` / `article` |
| limit | integer | ❌ | 返回数量，默认 20，范围 1~200 |
| format | string | ❌ | `markdown`（默认，直接给人/LLM 读）/ `json`（结构化数据） |

参数校验：`type`/`format` 非法值返回 HTTP 400 + `{"detail": "type 参数无效，可选值: all, feed, video, article"}`；`limit` 越界返回 422。

**format=markdown 输出示例**（每条含：序号、类型、作者、标题、发布时间、链接、阅读/赞/评论数据、标签、简介）：

```markdown
# Latest MFuns Content

## 1. 动态 by 今洲_teto39
标题: 我怎么老被炸啊…自爆山伯乐动态详情
发布时间: 2026-08-02 01:58:16
链接: `https://m.mfuns.net/feed/270889`
数据: 阅读 4 | 赞 2
标签: roblox,内脏与黑火药,GB

简介:
我怎么老被炸啊…
```

**format=json 输出示例**：

```json
[
  {
    "id": 270889,
    "type": "feed",
    "type_name": "动态",
    "title": "我怎么老被炸啊…自爆山伯乐动态详情",
    "url": "https://m.mfuns.net/feed/270889",
    "description": "…",
    "cover": "",
    "created_at": "2026-08-02 01:58:16",
    "created_at_timestamp": 1785607096.65,
    "author": "今洲_teto39",
    "author_id": "",
    "author_avatar": "https://resource.mfuns.net/static/xxx.gif",
    "author_bio": "8分钟前 移动端 4浏览",
    "author_fans": 45,
    "likes": 2, "dislikes": 0, "views": 4,
    "comments": 0, "favorites": 0, "rewards": 0, "danmaku": 0,
    "duration": 0,
    "category": "",
    "tags": "roblox,内脏与黑火药,GB"
  }
]
```

JSON 字段说明：

| 字段 | 类型 | 说明 |
| ---- | ---- | ---- |
| id | integer | 内容 ID（feed/video/article 各自的 ID） |
| type / type_name | string | `feed`动态 / `video`视频 / `article`文章；type_name 为中文名 |
| title | string | 标题 |
| url | string | 详情页链接（`m.mfuns.net/feed/{id}` / `/video/{id}` / `/article/{id}`） |
| description | string | 简介/正文摘要 |
| cover | string | 封面图 URL（动态可能为空） |
| created_at | string | 发布时间（`YYYY-MM-DD HH:MM:SS`） |
| created_at_timestamp | number | 发布时间时间戳（秒，浮点） |
| author / author_id / author_avatar / author_bio / author_fans | string/int | 作者信息（动态的 author_id 可能为空） |
| likes / dislikes / views / comments / favorites / rewards / danmaku | integer | 互动数据 |
| duration | integer | 时长（秒，仅视频有） |
| category | string | 分类 |
| tags | string | 标签，英文逗号分隔 |

## 2. 原始时间线：`GET /latest` ✅

| 参数 | 类型 | 必填 | 说明 |
| ---- | ---- | ---- | ---- |
| limit | integer | ❌ | 默认 50，范围 1~500 |
| type | string | ❌ | 内容类型过滤（`feed`/`video`/`article`），不传返回全部 |
| since | number | ❌ | 时间戳游标，只返回该时间之后的内容 |

响应：JSON 数组，结构与 `llm/latest` 的 json 格式一致，但 `created_at` 为时间戳数字。

## 3. 抓取统计：`GET /stats` ✅

响应示例（实测）：`{"feed": 3543, "video": 773, "article": 721}`。

---

> 官方站内没有公开的"关注动态流"接口（前端 `/follow/:uid` 为关注页路由），动态流场景建议直接用本第三方接口，或官方 `/v1/feeds/list`（全站动态列表，`start_id` 游标分页）。
