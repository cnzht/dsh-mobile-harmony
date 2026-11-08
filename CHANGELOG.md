# 迭代说明 / Changelog

本项目遵循语义化版本。日期为 Asia/Shanghai。

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
- **About 关于页**：作者 沛沛0518、仓库、MIT 许可、免责提示
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
