param(
  [string]$DevEcoHome = $env:DEVECO_HOME,
  [string]$P12,
  [string]$Cer,
  [string]$P7b,
  [string]$Alias = 'debugKey',
  [string]$StorePass,
  [string]$KeyPass
)
# Builds a RELEASE HAP for AppGallery submission.
# Without -P12/-Cer/-P7b it produces an unsigned release HAP (for inspection only;
# AppGallery will not accept it). With signing material it produces a signed release HAP.
$ErrorActionPreference = 'Stop'
if (-not $DevEcoHome) { $DevEcoHome = 'E:\HarmonyOS\DevEcoStudio' }
$proj = Split-Path -Parent $PSScriptRoot
Set-Location $proj

$env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'
$env:JAVA_HOME = Join-Path $DevEcoHome 'jbr'
$env:PATH = (Join-Path $DevEcoHome 'jbr\bin') + ';' + (Join-Path $DevEcoHome 'tools\node') + ';' + $env:PATH

Write-Host '== build release HAP ==' -ForegroundColor Cyan
& (Join-Path $proj 'hvigorw.bat') --mode module -p product=default -p module=entry@default `
    -p buildMode=release assembleHap
if ($LASTEXITCODE -ne 0) { throw 'release build failed' }

$unsigned = Join-Path $proj 'entry\build\default\outputs\default\entry-default-unsigned.hap'
if (-not (Test-Path $unsigned)) { throw "missing $unsigned" }
Write-Host "unsigned HAP: $unsigned"

if (-not ($P12 -and $Cer -and $P7b)) {
  Write-Host 'No release signing material supplied -> stop at unsigned HAP.' -ForegroundColor Yellow
  Write-Host 'AppGallery requires a release certificate issued by AppGallery Connect.' -ForegroundColor Yellow
  exit 0
}

$signTool = Join-Path $DevEcoHome 'sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar'
$signed = Join-Path $proj 'dist\dsh-mobile-release-signed.hap'
New-Item -ItemType Directory -Force -Path (Split-Path $signed) | Out-Null

Write-Host '== sign release HAP ==' -ForegroundColor Cyan
& (Join-Path $DevEcoHome 'jbr\bin\java.exe') -jar $signTool sign-app `
  -keyAlias $Alias -signAlg SHA256withECDSA `
  -mode localSign -appCertFile $Cer -profileFile $P7b `
  -inFile $unsigned -keystoreFile $P12 `
  -outFile $signed `
  -keyPwd $KeyPass -keystorePwd $StorePass
if ($LASTEXITCODE -ne 0) { throw 'signing failed' }
Write-Host "signed HAP: $signed" -ForegroundColor Green
