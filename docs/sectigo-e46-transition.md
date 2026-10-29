# 临时过渡补丁 v2：Mfuns API 与图片的 Sectigo E46 根证书兼容

2026-10-29 `api.mfuns.net` 使用的证书链可追溯至 Sectigo Public Server
Authentication Root E46。部分 Android 14 / 旧版 Dart TLS 信任库不能识别
这一新根，表现为 `CERTIFICATE_VERIFY_FAILED`。

## 做了什么

- 在 APK/桌面安装包中附带 **自签名 E46 根证书**，而非网站叶子证书。
- 启动时计算 DER 的 SHA-256 并与 Mozilla CCADB 公布的指纹核对。
- `SecurityContext(withTrustedRoots: true)` 保留系统受信根，并补充 E46。
- API 客户端继续使用专属上下文；同时补充本 Dart isolate 的 `SecurityContext.defaultContext`，覆盖 `Image.network` / `NetworkImage`。
- 默认上下文扩展影响本 isolate 内所有使用默认 `dart:io` 上下文的 HTTPS 请求，非仅图片域名；只增加已校验的 E46 根，保留正常 TLS 校验，不影响 WebView 或原生媒体库。
- 网络诊断增加 `resource.mfuns.net` 探测。
- 网络诊断中对 `api.mfuns.net` 的 HTTPS 测试使用相同兼容上下文，
  其他域名仍使用原有系统验证。
- 不允许错误证书，不取消主机名验证，保留原有证书有效期和签名链校验（不会新增撤销检查）。
- Web 平台和 `--dart-define=MFUNS_E46_COMPAT=false` 不启用补丁。
- 证书文件读取或校验失败时启动流程记录错误并退回系统证书库，
  不降低 TLS 安全性（相关设备可能继续无法访问 API）。

**证书来源**：
- Sectigo 官方证书列表：https://www.sectigo.com/knowledge-base/detail/Sectigo-Root-Certificates
- Mozilla CCADB：https://ccadb.my.salesforce-sites.com/mozilla/PrintViewForCase?CaseNumber=00001215

**E46 DER SHA-256**：
`c90f26f0fb1b4018b22227519b5ca2b53e2ca5b3be5cf18efe1bef47380c5383`

## 验证

```bash
openssl x509 -in assets/certs/sectigo-e46.pem -outform DER |
  sha256sum
flutter pub get
flutter test
flutter analyze
flutter run
```

需在曾经出现证书错误的 **Android 14** 设备上实际验证
`设置 → 网络诊断` 和动态详情等 API 请求；本补丁不保证修复其他证书错误。
桌面及其他支持平台应进行回归测试。

## 关闭 / 回滚

临时停用：

```bash
flutter build apk --release --split-per-abi --dart-define=MFUNS_E46_COMPAT=false
```

服务端应优先部署被客户端普遍信任的完整证书链（如可用的
Sectigo E46 → USERTrust ECC 交叉签名链）。
待服务端修复、旧 TLS 客户端升级且兼容性确认后，删除此补丁涉及的
`MfunsTls` 初始化、专用 HttpClient 调用、证书资源与测试。

不要使用 `badCertificateCallback = (_, _, _) => true`。

如图片仍报 HTTP 403/404、DNS、重定向或解码错误，应继续检查实际图片地址；添加根证书仅针对相应证书信任问题。域名根路径的 HTTPS 连通不代表具体图片可以成功加载。
