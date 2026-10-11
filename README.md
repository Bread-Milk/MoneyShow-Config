# MoneyShow server configuration

独立公开仓库，仅包含公开接口地址、配置版本、验证公钥和发布工具。此仓库不包含 App 源码、登录 token、数据库凭证或签名私钥。

## 当前配置

- 国内：`http://47.120.49.23`，启用。仅为当前版本已有 HTTP 地址保留兼容；新地址必须使用有效 HTTPS。
- 海外候选：`https://www.breadmilk.top`，**未启用**。尚未部署 MoneyShow 后端。
- `schemaVersion` 为 1，首次 `revision` 为 1。

客户端读取 `server-config.json`，其中 `payload` 是 `endpoints.json` 原始 UTF-8 字节的 Base64，`signature` 是这些字节的 Ed25519 签名。App 内置验证公钥，不能通过修改本仓库的公钥文件更换 App 的信任密钥。

公开配置来源：

- <https://raw.githubusercontent.com/Bread-Milk/MoneyShow-Config/main/server-config.json>
- <https://api.github.com/repos/Bread-Milk/MoneyShow-Config/contents/server-config.json?ref=main>，请求头 `Accept: application/vnd.github.raw+json`

两个入口都由 GitHub 提供，尚未部署独立 CDN 镜像。下载失败时 App 使用上次有效配置或内置国内地址。

## 更新地址

1. 修改 `endpoints.json`，增加 `revision`。保持 `schemaVersion: 1`。
2. 先验证新地址的 `/api/v1/health` 返回 `{"ok":true,"service":"moneyshow-server"}`，并验证有效 HTTPS、登录、订阅和识别额度的兼容性。
3. 在持有签名私钥的 Mac 上执行：

```sh
swift scripts/sign-config.swift endpoints.json server-config.json ~/.config/moneyshow/remote-config-ed25519.key
git diff --check
git add endpoints.json server-config.json signing-public-key.txt
git commit -m "Update server endpoints"
git push origin main
```

首次创建密钥时才添加 `--create-key`。默认私钥位置是 `~/.config/moneyshow/remote-config-ed25519.key`，文件权限为 0600；请将它保存在自己的受控备份中。工具不会输出私钥。私钥丢失后不能用新密钥给已发布 App 发送可信配置，需要更新客户端信任公钥。

只编辑 `endpoints.json` 而未重新签名不会更新 App。签名错误、不支持的结构、过期或冲突的 revision、新地址健康检查失败时，客户端保留旧配置。GitHub 分发存在缓存，App 支持 ETag 检查；成功发布不代表所有设备立即收到新内容。

## 海外入口

部署海外后端并确认 HTTPS、API 和账号/权益兼容后，将海外 `enabled` 改为 `true`，增加 revision，重新签名并发布。App 已有用户保持当前服务组，不因旅行、语言变更或连接超时自动跨组发送登录凭证；启用后可在设置中明确选择服务组。

## 回退

恢复上一地址时发布一个更高 revision 的配置并重新签名。不要直接恢复较旧的 `server-config.json`，客户端拒绝版本倒退。
