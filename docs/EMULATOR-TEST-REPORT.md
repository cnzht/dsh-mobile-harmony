# 模拟器端到端测试报告（1.0.3）

本文件记录 1.0.3 在 HarmonyOS 模拟器上的验证结果，用于说明"局域网完整功能与联网版
一致（除公网连接外），且没有闪退/白屏"。

## 被测物

| 项 | 值 |
|---|---|
| 设备 | HarmonyOS 模拟器，Mate 90 Pro 镜像，`7.0.0.107(SP8DEVC00E999R4P11)`，API 26 |
| 被测包 | `dist/harness-mobile-standalone-debug-signed.hap`（1.0.3 / 1000003） |
| 包 SHA-256 | `8F113337916B3F8FC4505997F290EF3C27B187032CC8282E3242AADFA22CE3B1` |
| 服务端 | 宿主机 `dsh web --host 127.0.0.1 --port 3100 --public-url http://10.0.2.2:3100` |
| 连接方式 | 模拟器内填 `http://10.0.2.2:3100/?token=…`（QEMU 用户网络把宿主 loopback 映射为 10.0.2.2） |
| 驱动 | `node --test tests/` + 基于 `hdc`/`uitest dumpLayout`/WinRT OCR 的 E2E 脚本 |

## 结果矩阵

| 阶段 | 内容 | 结果 |
|---|---|---|
| fresh | 首次启动：隐私弹窗（同意/不同意/暂不使用 + 隐私政策/用户协议）、同意后进本地演示页、示例会话、AI 内容标识、进入连接设置页、扫码入口 | 8/8 |
| lan | 输入局域网 URL → Connect → WebView 渲染 dsh web → 选择工作区 `AI WORK` → 进入聊天页（composer） | 6/6 |
| drawer | 原生顶栏 `Sessions` 抽屉：列出真实会话、点选切换、重新打开、`＋ New session` 进入 composer | 8/8 |
| about | About 卡：版本说明、开发者、MIT、局域网说明、关闭 | 5/5 |
| relaunch | 连上后 `aa force-stop` + 重启：自动恢复上次局域网地址、无多余提示 | 2/2 |
| neg | 公网地址被拒；失效 token 回配置页并提示；**无人监听的局域网地址**回配置页并提示且进程存活 | 39/39 |
| stab | 10 轮开关会话抽屉 + About + WebView 响应性 + hilog 无 crash 标记 | 5/5 |

合计 **73/73** 项检查通过。

## 本轮修掉的问题

1. **原生会话抽屉恒空**：会话行不是 `button`，改为按 `data-row-key="session:…"` 选行。
2. **注入脚本是语法错误**：`styleScript()` 少一个右花括号，整段桥接脚本被 ArkWeb 静默丢弃。
3. **连不存在的地址静默白屏**：新增 20 秒看门狗 + `onErrorReceive` 主框架处理，回配置页并提示。
4. **失败处理自身闪退**：Web 组件卸载后延迟探针调用 `WebviewController.runJavaScript`
   会同步抛 17100001（jscrash），全部调用改为经 `js()` + `webAlive` 守卫。
5. **不再注入上游 `mobile.css`**：该样式面向 dsh 0.1.5 DOM，注入当前版本会数秒后整页白屏；
   仅保留运行时小覆盖（不自动弹抽屉/遮罩、40 px 触控、composer 32vh）。

## 未覆盖 / 已知限制

- 模拟器无摄像头，**扫码连接未在模拟器上实测**（早期真机已验证扫码入口可见；扫码需要
  对端 `dsh web` 生成的二维码）。局域网手填地址链路已覆盖。
- 公网隧道/公网地址连接按设计被拒绝，属于单机版策略，不做端到端验证。
- 模拟器镜像的 dsh web 版本与用户实际部署版本可能不同；1.0.3 不依赖旧 DOM 类名
  （会话桥按 `data-row-key` 选行，缺失时回退 `_sessionRow`），换版本后抽屉仍可用。
