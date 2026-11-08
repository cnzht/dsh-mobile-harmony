# 隐私政策 / Privacy Policy

最后更新：2026-11-08

本隐私政策适用于 **DSH Mobile**（HarmonyOS 应用，包名以最终上架包名为准，以下简称"本应用"）。

## 1. 我们收集哪些信息

**本应用不收集任何个人信息。**

具体而言，本应用不会收集、上传或共享以下信息：

- 设备标识符（IMEI、OAID、序列号等）
- 地理位置
- 通讯录、短信、通话记录
- 相册、麦克风、摄像头内容（扫码仅用于读取二维码文本，图像不会被保存或上传）
- 用户行为、崩溃日志、使用统计

## 2. 应用会处理哪些数据

| 数据 | 存放位置 | 用途 | 是否外传 |
|---|---|---|---|
| 服务器地址（URL） | 设备本地应用私有存储 | 下次启动时回填，免重复输入 | 否 |
| 访问令牌（token） | 设备本地应用私有存储 | 连接用户指定的服务器 | 仅发送给该服务器本身 |
| 会话内容 | 不落盘（仅内存渲染） | 显示网页界面 | 仅在你与你的服务器之间传输 |

本应用不含任何统计、广告、推送、崩溃上报类第三方 SDK。

## 3. 网络访问说明

本应用唯一的网络行为是：**访问你在应用内填写的服务器地址**（局域网地址或公网地址）。
该服务器由你自行部署与运维，不属于本应用开发者。
因此你与该服务器之间的数据如何处理，取决于你自己的部署与配置。

## 4. 权限说明

| 权限 | 用途 |
|---|---|
| `ohos.permission.INTERNET` | 连接你指定的服务器以显示界面 |
| `ohos.permission.GET_NETWORK_INFO` | 判断网络是否可用，给出准确错误提示 |

本应用不申请相机权限以外的敏感权限；扫码功能使用系统扫码器，
若不使用扫码功能，可拒绝相机授权，手填地址同样可用。

## 5. 数据安全

- 服务器地址与令牌仅保存在设备本地的应用私有目录。
- 卸载应用即清除上述本地数据。
- 若你使用公网地址访问，建议自行启用 HTTPS；本应用不强制、也无法保证你所选服务器的安全性。

## 6. 未成年人

本应用面向开发者，不面向未成年人，也不收集未成年人信息。

## 7. 第三方

- 本应用为开源项目（MIT License）：<https://github.com/cnzht/dsh-mobile-harmony>
- 移动端适配层派生自开源项目 deepseek-harness-mobile（MIT）。
- 本应用与 DeepSeek、华为技术有限公司均无隶属、合作或背书关系。

## 8. 政策变更

本政策如有变更，将更新本页面并修改"最后更新"日期。继续使用即视为接受更新后的政策。

## 9. 联系方式

如有隐私相关问题，请通过以下方式联系：

- GitHub Issues：<https://github.com/cnzht/dsh-mobile-harmony/issues>

---

## English (summary)

DSH Mobile collects **no personal data**. The app stores only the server URL and
access token you enter, locally in app-private storage, and uses them solely to
connect to the server you specify. No analytics, advertising, push or crash-reporting
SDKs are included. Permissions used: `INTERNET` (reach your server) and
`GET_NETWORK_INFO` (accurate error messages). Camera access, if granted for QR
scanning, only decodes the QR text via the system scanner; images are not stored or
uploaded. This is an open-source (MIT) project, not affiliated with DeepSeek or Huawei.
Contact: <https://github.com/cnzht/dsh-mobile-harmony/issues>
