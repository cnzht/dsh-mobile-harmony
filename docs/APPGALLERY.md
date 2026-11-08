# 上架华为应用市场（AppGallery）指南

> 本文档说明如何把本项目打成可提交的发布包，以及 AppGallery Connect（AGC）侧的必填项。
> **上传动作必须在你的华为开发者账号下完成** —— 需要登录 AGC 控制台并提交审核，无法代做。

## 0. 现状与阻塞项

当前仓库可以直接构建调试包，但**不能直接上架**，原因有三个：

| 阻塞项 | 现状 | 要求 |
|---|---|---|
| 包名 | `com.example.helloharmony` | AGC 不允许 `com.example.*`，必须是自有域名反写，如 `cn.cnzht.dshmobile` |
| 签名 | 调试证书（DevEco 自动生成） | 必须使用 AGC 下发的**发布证书**（`*.cer` / `*.p7b` / `*.p12`） |
| 隐私政策 | 只有仓库里的 `DISCLAIMER.md` | 需要一个**可公开访问的 URL**（建议 GitHub Pages 或 Gist Raw） |

## 1. 在 AGC 创建应用

1. 打开 <https://developer.huawei.com/consumer/cn/service/josp/agc/index.html>
2. `我的应用 > 新建` → 选 `HarmonyOS` → 填：
   - **应用名称**：DSH Mobile
   - **应用包名**：`cn.cnzht.dshmobile`（创建后**不可修改**）
   - **默认语言**：中文
   - **应用分类**：工具 / 效率
3. 创建完成后进入应用，记下 **APP ID**（形如 `10xxxxxxx`）。

## 2. 生成发布证书

AGC 内：`应用信息 > 证书、APP ID和包名 > 证书` →

1. 新增证书 → 下载 `*.csr` 用途选择「发布证书」
2. 按页面指引用 keytool 生成密钥库并上传 CSR，换取 **`.cer`（发布证书）**
3. 生成 **`.p7b`（发布 Profile）**：`Profile > 添加` → 选择证书 → 勾选所需权限（本项目只用 `INTERNET`、`GET_NETWORK_INFO`）
4. 记录密钥库密码、alias、key 密码

> 这三个文件 + 密码就是后续签名所需，**务必不要提交到仓库**（`.gitignore` 已覆盖）。

## 3. 修改包名并本地签名

1. 改包名：`AppScope/app.json5` → `"bundleName": "cn.cnzht.dshmobile"`
2. DevEco：`File > Project Structure > Signing Configs`
   - 取消 `Automatically generate signature`
   - 填入上一步的 `p12 / cer / p7b`、alias、两个密码
   - 勾选 `Release` 构建类型
3. 命令行签名（或用本仓库脚本）：

```powershell
cd E:\HarmonyOS\Projects\dsh-mobile-harmony
.\scripts\build-release.ps1 `
  -P12  C:\keys\dsh-release.p12 `
  -Cer  C:\keys\dsh-release.cer `
  -P7b  C:\keys\dsh-release.p7b `
  -Alias releaseKey -StorePass **** -KeyPass ****
```

产物：`dist\dsh-mobile-release-signed.hap`

## 4. 生成 .app 发布包（推荐）

AGC 上传的是 **`.app`**（可含多 HAP）。用 IDE 生成最稳：

1. DevEco 菜单 `Build > Build App(s)/Hap(s) > Build App(s)`
2. 产物在 `entry/build/default/outputs/default/` 或 `build/outputs/` 下，形如 `xxx-signed.app`

> 命令行打包需要 `pack.info` 与 hap-list 参数，且必须与签名配置匹配，
> 直接用 IDE 的 `Build App(s)` 更可靠。

## 5. AGC 提交材料清单

| 项 | 要求 | 本项目建议 |
|---|---|---|
| 应用包 | 已签名的 `.app` | `dist/*.app` |
| 版本号 | `versionCode` 递增整数、`versionName` 语义化 | 现为 `1000000` / `1.0.0`，每次提审 `versionCode` 必须 +1 |
| 应用图标 | 216×216 / 1024×1024，PNG | 仓库 `docs/images` 有 1024 素材，`entry/.../media/app_icon.png` |
| 应用截图 | 每尺寸 3–5 张，手机建议 1080×2340 等 | 需重新截真机图（当前截图含 dsh 内容，注意遮挡隐私信息） |
| 隐私政策 URL | HTTPS 可访问 | 把 `DISCLAIMER.md` 发布到 GitHub Pages |
| 权限说明 | 逐个说明用途 | `INTERNET`：连接用户自建的 dsh 服务；`GET_NETWORK_INFO`：判断网络可用性 |
| 内容分级 | AGC 问卷 | 工具类，无社交/内容生成风险，但**应用会展示 AI 对话结果**，需如实勾选 |
| 敏感权限 | 本项目不申请相机/位置/通讯录 | 无需额外材料 |
| 测试账号 | 若审核需登录 | 本项目无需登录，但**必须提供可用的 dsh 服务地址**才能展示核心功能 |

> ⚠️ 关键风险：审核员通常无法访问你的 `dsh web`，应用会停在"输入地址/扫码"页。
> 建议在提交说明里写清楚「本应用是客户端，需配合用户自己的 DeepSeek Harness 服务」，
> 并提供一段录屏演示连接流程，降低被拒风险。

## 6. 常见拒绝原因（对照自查）

1. **包名为 com.example.\*** → 必须改
2. **使用调试证书签名** → 必须发布证书
3. **无可展示的核心功能**（审核员连不上你的服务）→ 提供演示视频 + 说明
4. **隐私政策缺失或与代码不符** → 本项目有网络访问，需写明
5. **应用名称/图标与功能不符** → 现名 DSH Mobile 与功能一致
6. **`versionCode` 与已上架版本冲突** → 首次提审无此问题

## 7. 审核通过后

- 发布范围（国家/地区）在 AGC 内选择
- 可配置分阶段发布（10% → 100%）
- 更新流程：`versionCode` +1 → 重新签名 → 上传 `.app` → 提审

## 8. 我能自动化到什么程度

- ✅ 已提供：`scripts/build-release.ps1`（release 构建 + 用你的证书签名）
- ✅ 已提供：`entry/obfuscation-rules.txt`（release 构建需要的混淆规则）
- ⚠️ 需要你提供：AGC 的 `p12/cer/p7b` + 密码（我不会写入仓库）
- ❌ 无法代做：登录你的华为开发者账号、填写审核问卷、提交审核

如果你有 AGC 的 **API 凭据**（client_id / client_secret）并确认可以自动化，我可以尝试用
AppGallery Connect API 上传发布包；否则请在 AGC 控制台手动上传 `dist\*.app`。
