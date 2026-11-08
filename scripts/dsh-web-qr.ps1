param(
  [string]$HostIp = '',
  [int]$Port = 0,
  [switch]$Open
)
# Starts `dsh web`, reads the single-use token URL it prints, and renders that URL
# as a QR PNG for the HarmonyOS app's "Scan QR code" button.
# The token is NOT fetched here, so it stays valid until the app scans it.
$ErrorActionPreference = 'Stop'
$cli = 'E:\Program Files (x86)\Harness\resources\runtime\cli\bin\dsh.cmd'
$qrMod = 'C:\Users\MAC\.dsh\profiles\desktop\node_modules\qrcode'
$outDir = 'E:\HarmonyOS\Projects\DshMobile\qr'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if ([string]::IsNullOrWhiteSpace($HostIp)) {
  $HostIp = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
      $_.IPAddress -notmatch '^127\.|^169\.' -and
      $_.InterfaceAlias -notmatch 'vEthernet|VMware|Loopback|Virtual' -and
      $_.PrefixOrigin -ne 'WellKnown'
    } |
    Sort-Object { if ($_.InterfaceAlias -match 'WLAN|Wi-Fi|Wireless') { 0 } else { 1 } } |
    Select-Object -First 1).IPAddress
}
if ($Port -le 0) {
  $used = (Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue).LocalPort
  $Port = 3090
  while ($used -contains $Port) { $Port++ }
}

$log = Join-Path $env:TEMP "dsh-web-$Port.log"
Remove-Item $log, "$log.err" -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $cli `
  -ArgumentList 'web', '--host', $HostIp, '--port', "$Port", '--no-open' `
  -RedirectStandardOutput $log -RedirectStandardError "$log.err" -WindowStyle Hidden | Out-Null

$url = $null
$deadline = (Get-Date).AddSeconds(60)
while (-not $url -and (Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 800
  $line = Get-Content $log -ErrorAction SilentlyContinue |
    Select-String -Pattern 'dsh web: (http\S+)' | Select-Object -First 1
  if ($line) { $url = $line.Matches[0].Groups[1].Value }
}
if (-not $url) {
  Write-Host "dsh web did not print a URL. stderr:" -ForegroundColor Red
  Get-Content "$log.err" -ErrorAction SilentlyContinue | Select-Object -Last 10
  exit 1
}

$stamp = Get-Date -Format 'HHmmss'
$png = Join-Path $outDir "dsh-web-$Port-$stamp.png"
$js = Join-Path $env:TEMP 'mkqr.js'
@'
const QR = require(process.argv[2]);
QR.toFile(process.argv[4], process.argv[3], { width: 720, margin: 2, errorCorrectionLevel: 'M' }, e => {
  if (e) { console.error('ERR', e.message); process.exit(1); }
  console.log('OK');
});
'@ | Set-Content $js -Encoding utf8

& node $js $qrMod $url $png | Out-Null

Write-Host "dsh web  : $url"
Write-Host "QR image : $png"
Write-Host "Open the QR on screen, then tap [Scan QR code] in DSH Mobile."
if ($Open) { Start-Process $png }
