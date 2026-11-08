# 提审说明文案（复制到 AGC「应用说明 / 测试说明」字段）

## 中文版（推荐直接使用）

```
【应用定位】
DSH Mobile 是 DeepSeek Harness（一款开源 AI 编码助手）的移动端客户端，
不是独立的内容服务。它本身不提供 AI 能力，也不内置任何服务器，
仅用于让用户通过手机访问「用户自己部署」的 DeepSeek Harness 服务。

【为什么打开是配置页】
应用首页需要用户填写自己服务器的地址（或扫码获取），这是设计如此，
而非功能缺陷。因此审核老师首次打开时看到的是"输入地址 / 扫码连接"页面。

【如何体验完整功能】
为了让审核老师能够体验，我们提供了以下两种方式（任选其一）：

方式一：录制演示视频（随提审附件提交）
  视频展示了从扫码配置 → 连接成功 → 进入会话 → 发送消息 的完整流程，
  时长约 60 秒，可完整说明核心功能。

方式二：临时体验服务器（提审期间有效）
  地址：<提审时填写，例如 https://<随机域名>/?token=<一次性令牌>
  说明：该地址为一次性访问令牌，仅供审核使用，有效期至审核结束。
        如失效，请通过下方联系方式索取新的体验地址。

【账号与登录】
应用无自有账号体系，不需要注册登录。
用户仅可选填自己服务器的访问令牌，用于连接其自建服务。

【权限说明】
1. ohos.permission.INTERNET
   用途：访问用户指定的 DeepSeek Harness 服务地址。
   必要性：应用核心功能就是连接并展示该服务界面，无此权限无法使用。
2. ohos.permission.GET_NETWORK_INFO
   用途：判断当前网络是否可用，在加载失败时给出准确提示。
   必要性：用于错误提示文案（"请检查网络" vs "地址不可达"）。

【数据与隐私】
- 应用不采集设备标识、位置、通讯录、相册等任何个人信息。
- 应用不向第三方服务器上报数据；所有数据往来仅发生在
  用户设备与其自己指定的服务器之间。
- 应用不使用统计 SDK、广告 SDK 或推送 SDK。
- 用户的服务器地址与访问令牌仅保存在设备本地（应用私有存储）。

【第三方与开源】
本应用为开源项目（MIT License），基于开源项目 deepseek-harness-mobile
的移动端适配层构建。与 DeepSeek、华为均无隶属或合作关系。

【联系方式】
GitHub: https://github.com/cnzht/dsh-mobile-harmony
（如需新的临时体验地址，请通过该仓库 Issue 联系）
```

## English version

```
[What this app is]
DSH Mobile is a mobile client for DeepSeek Harness, an open-source AI coding
assistant. The app itself provides no AI capability and hosts no server; it only
lets a user reach a DeepSeek Harness instance that the user deploys themselves.

[Why the first screen asks for an address]
The home screen intentionally asks for the user's own server URL (or a QR code).
A reviewer opening the app for the first time therefore sees a configuration
screen by design, not because functionality is missing.

[How to evaluate the core feature]
Option A - bundled demo video (attached to this submission): ~60s recording of
  scan -> connect -> open session -> send message.
Option B - temporary evaluation server (valid during review):
  URL: <fill in at submission time, e.g. https://<random-domain>/?token=<token>
  The URL carries a single-use token and is provided solely for review. If it
  expires, request a fresh one via the GitHub issue tracker below.

[Accounts]
No account system, no sign-up. A server access token is optional and only used
to connect to the user's own instance.

[Permissions]
1. ohos.permission.INTERNET - reach the user-specified Harness service; the app's
   core function is to render that service, so it cannot work without it.
2. ohos.permission.GET_NETWORK_INFO - determine network availability to produce
   accurate error messages ("check network" vs "host unreachable").

[Data and privacy]
- No device identifiers, location, contacts or photos are collected.
- No data is sent to any third-party server; traffic flows only between the user's
  device and the user's own server.
- No analytics, advertising or push SDKs.
- Server URL and access token are stored locally in app-private storage only.

[Third party / open source]
Open-source project (MIT). Built on the mobile adaptation layer of
deepseek-harness-mobile. Not affiliated with DeepSeek or Huawei.

[Contact]
GitHub: https://github.com/cnzht/dsh-mobile-harmony
```

## 提审时还要勾的字段

| 字段 | 建议填写 |
|---|---|
| 应用类别 | 工具 > 效率（或 开发者工具） |
| 内容分级问卷 | 应用会展示 AI 对话结果 → 「是否包含用户生成内容」勾 **是**，并说明内容来自用户自建服务 |
| 是否需要登录 | **否** |
| 是否有广告 | **否** |
| 儿童适用 | 否（面向开发者） |
| 隐私政策 URL | 见 `docs/PRIVACY.md`，需发布到可公开访问地址 |
| 测试说明 | 复制上面的中文版 |
| 附件 | 录屏 `demo.mp4`（按 `docs/DEMO-SCRIPT.md` 录制） |
