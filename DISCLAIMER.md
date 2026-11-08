# 免责声明 / DISCLAIMER

[简体中文](#简体中文) · [English](#english)

---

## 简体中文

本项目（`dsh-mobile-harmony`，以下简称"本项目"）是一个**个人实验性项目**，用于在 HarmonyOS 设备上访问 DeepSeek Harness（dsh）的 Web 界面。**请在使用前完整阅读本声明。**

### 1. 无担保

本项目按"现状"（AS IS）提供，**不附带任何形式的明示或默示担保**，包括但不限于对适销性、特定用途适用性、不侵权、无缺陷、持续可用或安全性的担保。作者不对本项目的正确性、稳定性、完整性或适用性作出任何承诺。

### 2. 使用风险自负

使用本项目即表示你理解并自愿承担全部风险，包括但不限于：

- **数据风险**：应用会加载并渲染远端 `dsh web` 的界面；若配置错误或遭受中间人攻击，可能导致会话内容、文件路径、工作区信息等泄露。
- **设备风险**：HarmonyOS 平台上的 WebView 注入、扫码、网络访问等能力可能因系统版本差异产生未知行为，极端情况下可能导致应用崩溃或系统异常。
- **账号与凭据风险**：若你将访问令牌（token）、Cookie 或华为开发者证书置于不安全的环境，可能造成凭据泄露与账号被滥用。
- **网络暴露风险**：本项目提供的公网访问方案（Cloudflare Quick Tunnel 等）会把服务暴露到互联网。其域名随机、默认无额外鉴权，仅依靠一次性 token 防护。**请勿长期开启，务必在调试结束后关闭隧道进程。**
- **合规风险**：你需要自行确保使用时遵守所在国家/地区的法律法规、网络服务商条款以及 DeepSeek Harness 的使用条款。

### 3. 责任限制

在任何情况下，作者及贡献者均**不对**因使用或无法使用本项目而产生的任何直接、间接、偶然、特殊、惩罚性或后果性损害承担责任，包括但不限于数据丢失、业务中断、利润损失、设备损坏或第三方索赔 —— 即使已被告知可能发生此类损害。

### 4. 非官方声明

本项目是**非官方、非商业**的第三方社区项目，与 DeepSeek、华为技术有限公司均**无隶属、合作或背书关系**。文中提及的 "DeepSeek"、"DeepSeek Harness"、"HarmonyOS"、"DevEco Studio"、"HUAWEI"、"Cloudflare" 等名称、商标与图标均归其各自权利人所有，本项目仅为描述性引用。

### 5. 上游项目与第三方内容

本项目的移动端适配层（`entry/src/main/resources/rawfile/` 下的 `early-polyfill.js`、`inject.js`、`mobile.css`）派生自开源项目
[Ajwyunsx/deepseek-harness-mobile](https://github.com/Ajwyunsx/deepseek-harness-mobile)（MIT License，Copyright (c) 2026 DeepSeek）。
相关版权与许可声明见 [NOTICE.md](NOTICE.md)。第三方内容的下游使用同样受其原始许可约束。

### 6. 安全建议（重要）

- 仅在**你拥有或已获明确授权**的设备与网络上使用。
- 调试用的调试证书与签名材料（`*.p12` / `*.cer` / `*.p7b`）**切勿**提交到公开仓库。
- 公网隧道（`trycloudflare.com`）仅用于临时调试；生产/长期使用请改用带鉴权与固定域名的方案，或使用端到端加密的中继（如 `ds-harness-remote`）。
- 若发现安全问题，请通过 GitHub Issue（不要公开敏感细节）或私下联系作者。

### 7. 变更

作者保留随时修改、暂停或终止本项目的权利，恕不另行通知。本声明可能随项目更新而变更，变更后继续使用即视为接受新版本。

---

## English

This project (`dsh-mobile-harmony`) is a **personal, experimental project** that lets a HarmonyOS device open the DeepSeek Harness (dsh) web UI. **Read this disclaimer in full before use.**

### 1. No warranty

The project is provided **"AS IS"**, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, non-infringement, absence of defects, continued availability, or security. The author makes no representation regarding correctness, stability, completeness, or suitability.

### 2. Use at your own risk

By using this project you accept all risk, including but not limited to:

- **Data**: the app renders a remote `dsh web` UI; misconfiguration or a man-in-the-middle can expose session content, workspace paths, and file metadata.
- **Device**: WebView script injection, barcode scanning, and network access may behave unexpectedly across HarmonyOS versions.
- **Credentials**: exposing access tokens, cookies, or Huawei developer signing material may leak credentials.
- **Network exposure**: the bundled public-access recipe (Cloudflare Quick Tunnel) publishes the service to the internet with a random hostname and no extra authentication beyond a single-use token. **Do not leave it running; stop the tunnel when you are done.**
- **Compliance**: you are responsible for complying with applicable laws, your network provider's terms, and DeepSeek Harness' own terms.

### 3. Limitation of liability

In no event shall the author or contributors be liable for any direct, indirect, incidental, special, punitive, or consequential damages (including loss of data, business interruption, loss of profits, device damage, or third-party claims) arising from the use or inability to use this project, even if advised of the possibility of such damages.

### 4. Not official

This is an **unofficial, non-commercial** community project. It is **not affiliated with, endorsed by, or sponsored by** DeepSeek or Huawei Technologies Co., Ltd. All product names, trademarks, and icons are the property of their respective owners and are used for descriptive purposes only.

### 5. Upstream and third-party content

The mobile adaptation layer (`early-polyfill.js`, `inject.js`, `mobile.css` under `entry/src/main/resources/rawfile/`) is derived from
[Ajwyunsx/deepseek-harness-mobile](https://github.com/Ajwyunsx/deepseek-harness-mobile) (MIT License, Copyright (c) 2026 DeepSeek).
See [NOTICE.md](NOTICE.md). Downstream use of that content remains subject to its original license.

### 6. Security advice

- Use only on devices and networks you own or are explicitly authorized to use.
- Never commit debug signing material (`*.p12` / `*.cer` / `*.p7b`) to a public repository.
- Treat the quick tunnel as temporary debugging infrastructure; for long-term use prefer an authenticated, fixed-domain setup or an end-to-end encrypted relay such as `ds-harness-remote`.
- Report security issues privately rather than posting exploit details publicly.

### 7. Changes

The author may modify, suspend, or discontinue this project at any time without notice. Continued use after a change to this disclaimer constitutes acceptance of the revised version.
