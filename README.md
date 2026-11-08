# DSH Mobile · HarmonyOS

把 DeepSeek Harness（dsh）的 Web 界面搬进 HarmonyOS 手机：
一个 ArkWeb 壳 + 上游移动端适配层，扫码即可连接局域网或公网上的 `dsh web`。

> 个人实验性项目 · 非官方 · 使用前请阅读 [免责声明](DISCLAIMER.md)

---

## 特性

- **扫码连接**：PC 端一条命令把 `dsh web` 地址（含一次性 token）渲染成二维码，手机点 `Scan QR code` 直接进
- **移动端适配层**：内置上游 `early-polyfill.js` / `inject.js` / `mobile.css`（约 62 KB），
  弹窗单列化、触控目标加大、代码块横向滚动等移动优化生效
- **外网访问**：内置 Cloudflare Quick Tunnel 一键脚本，无需端口转发
- **令牌失效自愈**：识别主框架 401/403 后退回配置页并回填旧地址
- **地址持久化**：`@ohos.data.preferences` 记住上次服务器地址

## 架构

```
ArkWeb(WebView)
  ├─ onPageBegin  → 注入 early-polyfill.js
  └─ onPageEnd    → 注入 inject.js + mobile.css（每个文档仅一次）
       ↓
  http(s)://<host>:<port>/?token=...
       ↓
  `dsh web`（运行在你的电脑或服务器）
```

上游 Android 版是 *proot Ubuntu 容器 + `dsh web` + WebView*；HarmonyOS 没有 proot/root 容器，
也无法在手机上跑 Node，所以本移植保留**移动端适配层**，把"本地跑服务"改成"连远端服务"。

## 环境要求

| 组件 | 版本（实测） |
|---|---|
| DevEco Studio | 26.0.0（build 261.x） |
| HarmonyOS SDK | 26.0.0 Release / **API 26** |
| 设备/模拟器 | HarmonyOS 7.0.0.130 或 API 26 模拟器 |
| 宿主机 `dsh` | 任一能跑 `dsh web` 的版本（0.1.5+ 有 token 鉴权） |

## 构建

### 方式 A：命令行

```bat
set DEVECO_HOME=C:\Program Files\Huawei\DevEco Studio
cd dsh-mobile-harmony
hvigorw.bat --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap
```

产物：`entry\build\default\outputs\default\entry-default-signed.hap`

`hvigorw.bat` 依次尝试 `DEVECO_HOME` → `DEVECO_SDK_HOME` 的父目录 → 常见安装路径。

### 方式 B：DevEco Studio

1. `File > Open` 选择本仓库目录
2. 右上角选择 `entry` 与目标设备 → ▶ Run

> **签名**：首次在你自己的机器构建，需要 `File > Project Structure > Signing Configs`
> 勾选 `Automatically generate signature`（需登录华为账号）。
> 华为自动签名的调试证书与 **bundleName 绑定**，改包名会报
> `00303074 The bundleName ... does not match the SigningConfig`。

## 宿主机：启动 `dsh web`

```powershell
# 绑定具体网卡 IP（不支持 0.0.0.0），打印带一次性 token 的 URL
dsh web --host 192.168.1.20 --port 3080 --no-open
# → dsh web: http://192.168.1.20:3080/?token=xxxxxxxx
```

- `--profile desktop` 会被拒绝（Desktop 档案由 Electron 独占），不要加
- token **一次性**：被访问过或服务重启即失效
- 手机与电脑需同一局域网；模拟器可用 `10.0.2.2` 指向宿主机

## 安装到设备

```bat
set HDC=%DEVECO_HOME%\sdk\default\openharmony\toolchains\hdc.exe
%HDC% list targets -v
%HDC% -t <serial> install -r entry\build\default\outputs\default\entry-default-signed.hap
%HDC% -t <serial> shell aa start -a EntryAbility -b com.example.helloharmony
```

USB 调试：手机 `设置 > 关于手机` 连点版本号进开发者模式 → `开发者选项 > USB 调试`。

## 扫码连接（推荐）

```powershell
# 局域网
.\scripts\dsh-web-qr.ps1 -Open
# 公网（Cloudflare Quick Tunnel）
.\scripts\dsh-public-qr.ps1 -Open
# token 过期后复用同一隧道换新 token
.\scripts\dsh-public-token.ps1 -Port 3100
```

脚本自动挑 WLAN 网卡 IP、找空闲端口、从 `dsh web` 的 stdout 解析 token URL，并用本地 `qrcode`
渲染 720px 二维码 PNG。**脚本不会访问该 URL，token 保持有效。**

手机端点 `Scan QR code` → 系统扫码器（`@kit.ScanKit`）→ 自动填入并连接。

> 脚本中 `qrcode` 模块路径默认取本机 pnpm 目录，换机器请改 `-QrModule` 参数，或 `npm i qrcode` 后调整路径。

## 调试要点（踩坑记录）

1. **输入框打不进字**：`TextInput({ text: state })` 单向绑定 + `onChange` 回写会每次按键重置输入法。
   → 改双向绑定 `TextInput({ text: $$this.draft })`。
2. **进入后自动弹侧栏 + 常驻蒙层**：dsh 在手机宽度首帧就把侧栏渲染成展开态，上游 `inject.js`
   据此启用抽屉模式，`#dsh-mobile-drawer-mask` 即那层蒙层。只摘 class 会在每次 DOM 变更被加回
   （实测每 ~500ms 开→关，表现为界面乱跳）。
   → 在 `mobile.css` 之后追加 override，把侧栏与蒙层钉成隐藏：
   ```css
   div[class*="_sidebarCol"]{display:none!important}
   #dsh-mobile-drawer-mask{display:none!important}
   ```
3. **重复注入**：token 入口是 302 链，`onPageEnd` 每跳都触发 → 按 URL 去重 + `window.__dshMobileAttached` 幂等守卫。
4. **注入顺序**：`inject.js` 必须在真实布局上运行；先插 CSS 会让它内部 DOM 查询抛
   `Cannot read properties of null (reading 'tagName')` → 保持 inject → CSS 顺序，并用 `try{}` 包裹。
5. **锁屏干扰自动化**：`hdc shell power-shell wakeup` + `power-shell setmode 602`；
   `uitest uiInput keyEvent Back` 在单页应用里等于退出应用，别用它收键盘。
6. **`00302013 The root node is not yet available`**：工程里若有 `node_modules/@ohos/hvigor*` 副本，
   核心与插件会各加载一份实例 → 删掉副本，统一走 IDE 自带引擎。

验收技巧：用 `runJavaScript` 返回 JSON 打到 `hilog`，`hdc shell "hilog -x | grep DshMobile"` 读取，
比截图更适合判断 DOM 状态（例如测量侧栏宽度、遮罩 `display`、横向溢出）。

## 目录结构

```
AppScope/                 应用级配置（bundleName / 版本 / 图标）
entry/
  src/main/
    ets/pages/Index.ets   全部界面与注入逻辑
    ets/entryability/     UIAbility
    resources/rawfile/    上游移动适配层
    resources/base/       图标与字符串
    module.json5          权限：INTERNET / GET_NETWORK_INFO
build-profile.json5       API 26 / runtimeOS=HarmonyOS / signingConfigs
hvigorw.bat               可移植构建入口
scripts/                  二维码与验证辅助脚本（Windows PowerShell）
docs/images/              截图
```

## 安全须知

- 公网隧道（`trycloudflare.com`）仅适合临时调试：域名随机、无额外鉴权、进程退出即失效。
  **调试结束请关闭隧道进程。**
- 不要提交 `*.p12` / `*.cer` / `*.p7b`、token、设备序列号（`.gitignore` 已覆盖）。
- 长期使用建议改用带鉴权 + 固定域名的反向代理，或端到端加密中继（如 `ds-harness-remote`）。

## 已知限制

- **不显示 dsh 左侧会话栏**：见第 2 条，上游抽屉依赖父级容器显隐；当前选择视觉稳定优先。
- 模拟器无摄像头，扫码只能用真机；模拟器请手填 URL。
- 自签 HTTPS 会被 WebView 拦截，公网请用受信任证书（Quick Tunnel 自带）。

## 许可

[MIT](LICENSE) · 免责声明见 [DISCLAIMER.md](DISCLAIMER.md) · 第三方声明见 [NOTICE.md](NOTICE.md)
