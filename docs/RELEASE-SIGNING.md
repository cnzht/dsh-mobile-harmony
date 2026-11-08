# 发布签名实测流程（已验证可用）

本文件记录**实际跑通**的发布签名步骤，可直接复现。所有路径以本机为例，换机请自行替换。

## 0. 需要的文件

| 文件 | 来源 | 本例路径 |
|---|---|---|
| 密钥库 `*.p12` | 本地 `keytool` 生成 | `keys\dsh-release.p12` |
| CSR `*.csr` | 由密钥库导出，上传 AGC | `keys\dsh-release.csr` |
| 发布 Profile `*.p7b` | AGC `Profile > 添加` 下载 | `keys\dsh-mobile-release-profile-2026Release.p7b` |
| 发布证书（应用证书链） | **见下方第 1 节** | `keys\release-chain.pem` |

## 1. ⚠️ 应用证书从哪来（本例踩过的坑）

AGC 证书页点"下载"给出的 `*.cer` **可能是根证书**
（`subject=Huawei CBG Root CA G2`），不是应用发布证书。

真正的应用发布证书**内嵌在 `.p7b` 里**。用 `hap-sign-tool` 解析出来：

```powershell
$sign = 'E:\HarmonyOS\DevEcoStudio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
& "$DevEcoHome\jbr\bin\java.exe" -jar $sign verify-profile `
    -inFile keys\dsh-mobile-release-profile-2026Release.p7b `
    -outFile keys\profile-dump.json
```

从 `profile-dump.json` 取两个关键字段：

- `content.bundle-info.bundle-name` → 应用包名（本例 `cn.cnzht.dshmobile`）
- `content.bundle-info.distribution-certificate` → **应用发布证书（PEM）**

```powershell
$p = Get-Content keys\profile-dump.json -Raw | ConvertFrom-Json
$p.content.'bundle-info'.'bundle-name'
$p.content.'bundle-info'.'distribution-certificate' | Set-Content keys\profile-cert.cer -Encoding ascii
```

## 2. 拼出完整证书链（app → 中间 CA → 根 CA）

`sign-app` 要求 `-appCertFile` 是**证书链**，只给应用证书会报
`11013004 Profile cert must a cert chain`。

中间 CA `Huawei CBG Developer Relations CA G2` 可从 DevEco 自动生成的调试证书里提取
（同一个 CA），也可从 AGC 证书 ZIP 里拿。调试证书路径：
`%USERPROFILE%\.ohos\config\default_<应用名>_*.cer`（内含 3 张证书）。

```powershell
$openssl = 'C:\Program Files\Git\usr\bin\openssl.exe'
$all = Get-Content "$env:USERPROFILE\.ohos\config\default_*.cer" -Raw   # 取实际文件
$blocks = [regex]::Matches($all, '(?s)-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----') |
          ForEach-Object { $_.Value }
# 找出 issuer=Root CA G2 且 subject 含 Developer Relations CA G2 的那张
# 再取 subject/issuer 均为 Root CA G2 的自签根证书
$chain = (Get-Content keys\profile-cert.cer -Raw).Trim() + "`n" + $inter.Trim() + "`n" + $root.Trim()
$chain | Set-Content keys\release-chain.pem -Encoding ascii
```

校验链顺序：

```powershell
& $openssl crl2pkcs7 -nocrl -certfile keys\release-chain.pem | & $openssl pkcs7 -print_certs -noout
# 期望依次为：<你的应用证书> → Huawei CBG Developer Relations CA G2 → Huawei CBG Root CA G2
```

## 3. 改包名并构建（无签名配置）

`bundleName` 必须与 Profile 里的 `bundle-name` **完全一致**，否则签名会失败。

```json5
// AppScope/app.json5
"bundleName": "cn.cnzht.dshmobile",
```

`build-profile.json5` 里 **不要**保留调试 `signingConfigs`（它绑定旧包名，会报
`bundleName ... does not match the SigningConfig`）。清空即可，签名由命令行完成。

```powershell
# HAP
.\hvigorw.bat --mode module -p product=default -p module=entry@default -p buildMode=release assembleHap
# APP（应用市场提交用；必须在 project 模式）
.\hvigorw.bat --mode project -p product=default -p buildMode=release assembleApp
```

产物：
- `entry\build\default\outputs\default\entry-default-unsigned.hap`
- `build\outputs\default\<Project>-default-unsigned.app`

> 任务名是 `assembleApp`，且**只有 project 模式**有；module 模式会报 `Task not found`。

## 4. 签名（HAP 与 APP 都能签）

```powershell
$sign  = 'E:\HarmonyOS\DevEcoStudio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
$java  = "$DevEcoHome\jbr\bin\java.exe"
$pw    = '<密钥库密码>'

& $java -jar $sign sign-app `
  -keyAlias releaseKey -signAlg SHA384withECDSA -mode localSign `
  -appCertFile keys\release-chain.pem `
  -profileFile keys\dsh-mobile-release-profile-2026Release.p7b `
  -inFile <unsigned.hap 或 unsigned.app> `
  -keystoreFile keys\dsh-release.p12 `
  -outFile <signed 输出> `
  -keyPwd $pw -keystorePwd $pw
```

`-signAlg` 必须与密钥算法匹配：`secp384r1` → `SHA384withECDSA`。

## 5. 校验与试装

```powershell
# 校验签名（会打印 verify-app success）
& $java -jar $sign verify-app -inFile dist\dsh-mobile-release-signed.hap `
   -outCertChain keys\out-chain.cer -outProfile keys\out-profile.p7b

# 试装（release Profile 不绑定设备，模拟器/真机都能装）
hdc install -r dist\dsh-mobile-release-signed.hap
hdc shell bm dump -n cn.cnzht.dshmobile | Select-String bundleName
```

## 6. 提交 AGC

上传 `dist\dsh-mobile-release-signed.app`（推荐）或 `.hap`，
配合 `docs/SUBMISSION-NOTES.md` 的文案与 `docs/DEMO-SCRIPT.md` 的录屏。

## 7. 实测结果（2026-11-08）

| 步骤 | 结果 |
|---|---|
| Profile 解析 | `bundle-name=cn.cnzht.dshmobile`、`type=release`、`apl=normal`（无 ACL） |
| 证书与密钥库匹配 | 公钥 SHA256 一致（`409938bf…6ddf`） |
| HAP 签名 | `sign-app success`，204 KB |
| APP 签名 | `sign-app success`，102 KB |
| 验签 | `verify-app success` |
| 安装（模拟器 API 26） | `install bundle successfully`（包名 `cn.cnzht.dshmobile`） |

## 8. 注意

- 密钥库与 `PASSWORD.txt` **不要提交仓库**（`.gitignore` 已覆盖 `*.p12/*.cer/*.p7b`）
- Profile 有效期约 3 年（本例 2026-11-08 → 2029-11-08），到期需重新生成
- `versionCode`（现 `1000000`）每次重新提审必须递增
