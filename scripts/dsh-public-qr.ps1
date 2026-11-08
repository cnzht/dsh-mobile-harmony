param(
  [int]$Port = 0,
  [string]$Cloudflared = 'E:\HarmonyOS\tools\cloudflared.exe',
  [switch]$Open
)
# Publishes `dsh web` to the internet through a Cloudflare quick tunnel and renders
# the public, tokenized URL as a QR PNG for DSH Mobile's "Scan QR code".
#
# Order matters: the tunnel hostname is random, and `dsh web` bakes it into the
# printed URL and the /api browser-trust fence, so the tunnel starts first and
# dsh is then given --public-url / --trusted-host.
$ErrorActionPreference = 'Stop'
$cli = 'E:\Program Files (x86)\Harness\resources\runtime\cli\bin\dsh.cmd'
$qrMod = 'C:\Users\MAC\.dsh\profiles\desktop\node_modules\qrcode'
$outDir = 'E:\HarmonyOS\Projects\DshMobile\qr'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if ($Port -le 0) {
  $used = (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue).LocalPort
  $Port = 3100
  while ($used -contains $Port) { $Port++ }
}

# 1) quick tunnel to loopback
$cfLog = Join-Path $env:TEMP "cf-$Port.log"
Remove-Item $cfLog -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $Cloudflared `
  -ArgumentList 'tunnel', '--url', "http://127.0.0.1:$Port", '--no-autoupdate' `
  -RedirectStandardOutput $cfLog -RedirectStandardError "$cfLog.err" -WindowStyle Hidden | Out-Null

$public = $null
$deadline = (Get-Date).AddSeconds(90)
while (-not $public -and (Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 900
  $hit = (Get-Content $cfLog, "$cfLog.err" -ErrorAction SilentlyContinue |
    Select-String -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' | Select-Object -First 1)
  if ($hit) { $public = $hit.Matches[0].Value }
}
if (-not $public) {
  Write-Host 'cloudflared did not report a public URL:' -ForegroundColor Red
  Get-Content "$cfLog.err" -ErrorAction SilentlyContinue | Select-Object -Last 12
  exit 1
}
$hostName = ([uri]$public).Host
Write-Host "tunnel   : $public"

# 2) dsh web behind the tunnel, advertised under the public host
$dshLog = Join-Path $env:TEMP "dsh-pub-$Port.log"
Remove-Item $dshLog, "$dshLog.err" -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $cli `
  -ArgumentList 'web', '--host', '127.0.0.1', '--port', "$Port", '--no-open', `
    '--public-url', "$public/", '--trusted-host', $hostName `
  -RedirectStandardOutput $dshLog -RedirectStandardError "$dshLog.err" -WindowStyle Hidden | Out-Null

$url = $null
$deadline = (Get-Date).AddSeconds(60)
while (-not $url -and (Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 900
  $line = Get-Content $dshLog -ErrorAction SilentlyContinue |
    Select-String -Pattern 'dsh web: (http\S+)' | Select-Object -First 1
  if ($line) { $url = $line.Matches[0].Groups[1].Value }
}
if (-not $url) {
  Write-Host 'dsh web did not print a URL:' -ForegroundColor Red
  Get-Content "$dshLog.err" -ErrorAction SilentlyContinue | Select-Object -Last 12
  exit 1
}

$stamp = Get-Date -Format 'HHmmss'
$png = Join-Path $outDir "dsh-public-$Port-$stamp.png"
$js = Join-Path $env:TEMP 'mkqr.js'
@'
const QR = require(process.argv[2]);
QR.toFile(process.argv[4], process.argv[3], { width: 720, margin: 2, errorCorrectionLevel: 'M' }, e => {
  if (e) { console.error('ERR', e.message); process.exit(1); }
  console.log('OK');
});
'@ | Set-Content $js -Encoding utf8
& node $js $qrMod $url $png | Out-Null

Write-Host "public   : $url"
Write-Host "QR image : $png"
Write-Host "Scan it in DSH Mobile - works from any network, no port forwarding."
if ($Open) { Start-Process $png }
