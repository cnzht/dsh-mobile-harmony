# 迭代说明 / Changelog

本项目遵循语义化版本。日期为 Asia/Shanghai。

## 1.0.1 — 2026-11-12

华为应用市场 1.0.0 审核驳回（12 条）整改版。包名 `cn.cnzht.dshmobile` 不变，
版本 `1.0.1 (versionCode 1000001)`。逐条状态见 [docs/RESUBMISSION-CHECKLIST.md](docs/RESUBMISSION-CHECKLIST.md)。

### 新增（Added）

- **首启隐私弹窗**：首次启动用 ArkUI 覆盖层展示隐私政策摘要，附隐私政策 / 用户协议入口；
  点"同意"后把标记写入 preferences，以后不再弹；"不同意"显示需同意才能使用的提示，
  "暂不使用"关闭弹窗但首页保留横幅入口。首页页脚新增常驻"隐私政策 / 用户协议"链接。
  沿用 About 的覆盖层模式（AlertDialog 在真机上不可靠）。
- **AI 内容显式标识**：聊天页顶栏常驻"AI 生成内容"徽标；About 增加"会话内容由你自部署
  的服务生成，本应用仅负责展示，不提供 AI 生成服务"说明。重新提审的证明材料：
  徽标截图 + 一次真实会话截图。
- **无依赖测试套件（`tests/`，只用 Node 内置 `node:test` + `node:assert`）**：
  跑法 `node --test tests/`（经 `tests/index.js` 入口；本机 Node 24.22.1
  不展开目录参数，也可用 `node --test "tests/**/*.test.js"` 或裸 `node --test`），
  不需要联网、不需要 DevEco，共 56 个测试，全部通过。
  - `tests/polyfills.test.js`：`early-polyfill.js` 在删掉现代 API 的 vm 上下文里实跑
    （`AbortSignal.any/timeout`、`Promise.withResolvers`、`findLast/findLastIndex/toReversed/toSpliced`、
    `Object/Map.groupBy`）。
  - `tests/inject.test.js`：`inject.js` 对最小 fake DOM（`tests/support/fake-dom.js`，
    含可控时钟、`MutationObserver`、`requestAnimationFrame`，无 jsdom）实跑：
    幂等守卫、viewport、详情栏三态、侧栏抽屉、统计条打标、弹窗夹取、tooltip 自藏、
    输入框防遮挡、配置拦截、插件安装流程。
  - `tests/static.test.js`：两 JS 文件 `node --check`、CSS 大括号平衡、仅申请 `INTERNET` 权限、
    包名 `cn.cnzht.dshmobile`、无硬编码 token/密码/私钥、无签名材料入库、无内嵌服务器地址。
  - `tests/index-ets.test.js`：`Index.ets` 的 `toTitleList` 从源码抽出、去 ArkTS 类型后实跑
    （空串/非法 JSON/非数组/超 30 截断），并静态断言 `connect()` 空地址报错、
    仅主框架 401/403 回 setup、`injectOnce` 去重。

### 修复（Fixed）

- **应用改名 Harness Mobile（驳回第 2、8、9 条）**：提交名"DSH 鸿蒙版移动版"与终端显示名
  "DSH Mobile"不一致，且名字含"鸿蒙"商标、介绍含"DeepSeek"商标。现五处统一为
  **Harness Mobile**：控制台提交名、`app_name`、`EntryAbility_label`、首页标题、About 标题；
  应用内、应用介绍、隐私政策、用户协议、演示脚本、README 中所有"DeepSeek"品牌词与"鸿蒙"二字
  全部删除，改用"Harness"或"AI 编码助手"等中性表述。上游开源归属只保留 NOTICE.md 里
  事实性的 MIT 归属链接。
- **About 开发者名称与开发者中心不一致（驳回第 1 条）**：About 原显示"沛沛0518"，
  改为开发者中心登记的真实姓名（真实姓名不写入仓库），由构建机本地 developer.json 提供；用户协议、隐私政策中的开发者表述同步改为登记名。
  同时删掉 About 里"Personal experimental project…Use at your own risk."（自称实验品对审核不利）。
- **隐私政策链接 404（驳回第 5 条）**：提交的 `https://cnzht.github.io/dsh-mobile-harmony/privacy.html`
  打不开，原因是仓库根本没开 GitHub Pages。解法见清单：启用 Pages（源选 main 分支 `/docs`），
  或在 AGC 里改用隐私托管服务（后者更稳）；提审前先在无痕窗口打开确认。
- **顶栏 Sessions 按钮文案永远不变**：按钮用 `this.sessionsOpen ? 'Close' : 'Sessions'`，
  但 `toggleSessions()` 只改 `drawerOpen`、从不改 `sessionsOpen`，文案恒为 Sessions。
  改为以 `drawerOpen` 为准，并删除已无任何读写方的死状态 `sessionsOpen`；
  `backToSetup()` 改为同步清理 `drawerOpen` 和 `sessionsList`（之前只清了死状态，
  返回配置页后抽屉状态和旧会话列表会残留）。
- **`Array.prototype.toSpliced` 缺省 deleteCount 时行为错误**：旧实现把
  `[start, undefined]` 传给 `splice`，`deleteCount` 被当成 0，于是 `toSpliced(1)`
  返回完整拷贝而非截断结果。改为把 `arguments` 原样透传给 `splice`。
- **`Object.groupBy` 丢 `"__proto__"` 分组**：旧实现用 `{}` 做目标对象，该 key 会悄悄变成
  原型、从 `JSON.stringify` 里消失。改为 `Object.create(null)`。
- **`Array.prototype.findLast/findLastIndex` 会命中稀疏数组的空洞**：旧实现没跳过
  `!(i in this)` 的下标，`findLastIndex(x => x === undefined)` 会在空洞处误报。
  改为跳过空洞，与原生行为一致。
- **`ensureViewport` 在没有 viewport meta 时什么都不做**：旧实现只在已有 meta 且内容不对时才改，
  无 meta 的页面仍按桌面宽度排版。改为缺失时新建一个 meta（挂到 `document.head`，
  无 head 时挂 `document.documentElement`）。

### 变更（Changed）

- `inject.js` 与 `early-polyfill.js` 里的 `AbortSignal.any/timeout` 重复实现加注释说明：
  是刻意重复（early 在 onPageBegin、inject 在 onPageEnd，前者漏跑时后者兜底），
  不是漏删；两者行为一致，改一处就要改另一处，`tests` 里有文本一致性检查。
  未做大重构，应用行为、包名、签名/发布流程均未改动。

### 未解决（代码层面无法解决，需用户在控制台 / 真机上完成）

- **演示录屏（驳回第 3 条）**：审核要求 HarmonyOS 设备录制的演示录屏（从启动开始、完整核心功能），
  上传到自测文件。录屏只能在真机上录，见 [docs/DEMO-SCRIPT.md](docs/DEMO-SCRIPT.md)；只在备注里写
  "已附视频"不算数，1.0.0 就是这样被拒的。
- **实名认证（驳回第 4 条）**：应用无账号、无登录，做不了手机号/身份证核验。处理方式是备注文案讲清
  应用不提供 AI 生成服务、不设账号，访问控制由用户自己的服务器令牌实现。如果审核仍坚持，
  这条需要走正式的合规流程，代码层面无法解决，不要假装修好了。
- **AI 文本生成资质与算法备案（驳回第 10、12 条）**：《安全评估报告》+ 全国互联网安全服务管理平台
  提交结果截图，代码无法提供。备注文案已讲清应用无 AI 生成模块；如果审核坚持需要正式办理，
  见清单里的用户侧待办与风险说明。
- **APP 类型信息**：1.0.0 误选了"单机APP"，重新提审时在控制台改为**联网**。

### 已知限制

- 本套件只能验证可脱离 HarmonyOS 跑的逻辑；ArkTS 页面真实渲染、WebView 加载真实 dsh 地址、
  原生 `DshNative` 桥接、HAP 构建与签名、真机 dsh 页面的真实 DOM 类名，仍需真机/DevEco 验证。
  详见 `tests/README.md` 的 "What this suite cannot verify"。
- 本次整改同样未在真机/DevEco 上验证：首启隐私弹窗、AI 徽标、改名后的显示效果，
  均须在提审前于真机上确认（录演示录屏时顺带验证）。

## v1.0.0 — 2026-11-08

首个可上架版本（HarmonyOS API 26）。

### 新增（Added）

- **ArkWeb 外壳**：加载远端 `dsh web`，注入上游移动端适配层
  （`early-polyfill.js` / `inject.js` / `mobile.css`，约 62 KB）
- **扫码连接**：调用 `@kit.ScanKit` 系统扫码器，扫描 PC 端生成的带令牌二维码
- **连接进度层**：`LoadingProgress` + `Connecting…`，`onPageBegin/onPageEnd` 驱动显隐
- **原生会话抽屉**：ArkUI `List` 抽屉，通过注入脚本从 dsh 侧栏提取会话标题，
  点击后回调 WebView 完成跳转；支持"新会话"
- **令牌失效自愈**：主框架 401/403 → 退回配置页并回填地址
- **地址持久化**：`@ohos.data.preferences`
- **About 关于页**：开发者（登记名）、仓库、MIT 许可、免责提示
- **首页 GitHub 链接**：`UIAbilityContext.openLink()`
- **应用图标**：分层图标（渐变背景 + 对话气泡 + 终端提示符），
  并提供 AGC 所需 216/512/1024 与圆角透明版本
- **上架素材与文档**：5 张 1920×1080 商店截图、隐私政策、用户协议、上架指南、
  表单填写内容、60 秒演示录屏脚本

### 修复（Fixed）

- **进入后界面乱跳**：上游按"侧栏是否展开"反复启用抽屉模式，实测每 ~500 ms 开关一次 →
  改为 CSS 钉死侧栏与遮罩 + 原生抽屉替代
- **常驻蒙层**：Web 模式下根级半透明浮层遮挡 → 改为 34 vp 不透明细条
- **首页文字被裁**：固定 `Column` 居中导致内容超高被切 → 改为 `Scroll` + `maxLines`
- **TextInput 无法输入**：单向绑定重置输入法 → 双向绑定 `$$this.draft`
- **软键盘遮挡输入框**：补 `keyboardAvoidMode(RESIZE_CONTENT)`
- **About 在真机不弹出**：`AlertDialog.show()` 在该机型无效 → 改为根级 ArkUI 覆盖层
- **`ForEach ... does not have forEach`** 崩溃：注入返回值经 `JSON.parse` 后不是数组 →
  增加 `Array.isArray` 防御转换
- **重复注入**：302 链导致每跳注入一次 → 按 URL 去重 + JS 幂等守卫
- **注入顺序错误**：先插 CSS 使 `inject.js` 抛 `tagName of null` → 改回 inject → CSS，并用 `try{}` 包裹
- **权限冗余**：移除从未调用的 `ohos.permission.GET_NETWORK_INFO`，仅保留 `INTERNET`，
  同时避免 AGC Profile 的 ACL 校验困扰

### 变更（Changed）

- **包名**：`com.example.helloharmony` → **`cn.cnzht.dshmobile`**
  （`com.example.*` 不被应用市场接受；需与 AGC Profile 的 `bundle-name` 一致）
- **签名方式**：调试自动签名 → AGC 发布证书命令行签名
  （`hap-sign-tool sign-app`，`SHA384withECDSA`/secp384r1）
- **`.app` 打包**：改用 `hvigorw --mode project assembleApp`
  （module 模式下无该任务）
- **构建入口**：`hvigorw.bat` 改为按 `DEVECO_HOME` / `DEVECO_SDK_HOME` 自动定位 IDE

### 移除（Removed）

- 仓库中的原始调试截图（可能含地址栏内容）→ 仅保留统一遮盖地址输入区的商店图
- 工程内 `node_modules/@ohos/hvigor*` 副本（导致 hvigor 双实例报错）

### 安全与隐私

- 仓库不含任何签名材料（`*.p12/*.cer/*.p7b`）、访问令牌、设备序列号
- 上架文档中的 App ID / 邮箱 / 姓名已替换为占位符
- 应用不收集个人信息，无统计/广告/推送 SDK

### 已知问题（Known Issues）

- dsh 原生左侧栏未在移动端呈现（改用原生会话抽屉）
- AGC 发布证书签名的包无法 `hdc` 侧载到零售真机，仅可经应用市场安装
- 模拟器无摄像头，扫码功能需真机验证
