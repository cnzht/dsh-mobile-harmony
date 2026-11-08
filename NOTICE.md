# NOTICE — 第三方组件与许可

本项目自身以 MIT License 发布（见 [LICENSE](LICENSE)）。下列第三方内容保留其原始版权与许可。

## 1. 上游项目

| 项目 | 许可 | 版权 |
|---|---|---|
| [Ajwyunsx/deepseek-harness-mobile](https://github.com/Ajwyunsx/deepseek-harness-mobile) | MIT License | Copyright (c) 2026 DeepSeek |

**派生说明**：以下文件原样取自上游 `dsh-mobile/app/src/main/assets/`，未做修改：

```
entry/src/main/resources/rawfile/early-polyfill.js
entry/src/main/resources/rawfile/inject.js
entry/src/main/resources/rawfile/mobile.css
```

上游 Android 实现为 *proot Ubuntu 容器 + `dsh web` + WebView 移动适配*。
本项目在 HarmonyOS 上无法运行容器，因此只移植了其中的**移动端适配注入层**，
并把"手机本地跑服务"改为"连接局域网 / 公网上的 `dsh web`"。

## 2. 构建与运行依赖（不随本仓库分发）

| 组件 | 许可/说明 | 来源 |
|---|---|---|
| HarmonyOS SDK（API 26） | 华为开发者协议 | DevEco Studio 安装包 |
| DevEco Studio | 华为开发者协议 | 华为开发者联盟 |
| hvigor / ohpm | 华为开发者协议 | IDE 内置 |
| Cloudflare `cloudflared` | Apache License 2.0 | Cloudflare 官方发布 |

## 3. 商标

DeepSeek、DeepSeek Harness、HarmonyOS、DevEco Studio、HUAWEI、Cloudflare 等名称与徽标
归其各自权利人所有。本项目仅在描述性语境下引用，不代表任何隶属或背书关系。

## 4. 安全提示

本仓库**不包含**任何签名材料（`*.p12` / `*.cer` / `*.p7b`）、访问 token、Cookie 或设备序列号。
若你 fork 本项目，请同样避免提交上述内容。
