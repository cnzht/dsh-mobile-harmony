param(
  [int]$Port = 3100,
  [string]$PublicHost = '',
  [string]$QrModule = 'C:\Users\MAC\.dsh\profiles\desktop\node_modules\qrcode'
)
# Re-issues the single-use token for an ALREADY-RUNNING quick tunnel: keeps the
# same trycloudflare hostname, restarts only `dsh web` behind it, and renders the
# new tokenized URL as a QR PNG.
$ErrorActionPreference = 'Stop'
$cli = 'E:\Program Files (x86)\Harness\resources\runtime\cli\bin\dsh.cmd'
$outDir = 'E:\HarmonyOS\Projects\DshMobile\qr'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if ([string]::IsNullOrWhiteSpace($PublicHost)) {
  $cfLog = Get-ChildItem $env:TEMP -Filter 'cf-*.log*' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $hit = Get-Content $cfLog.FullName -ErrorAction SilentlyContinue |
    Select-String -Pattern 'https://([a-z0-9-]+\.trycloudflare\.com)' | Select-Object -First 1
  if (-not $hit) { throw 'No running quick tunnel found; run dsh-public-qr.ps1 first.' }
  $PublicHost = $hit.Matches[0].Groups[1].Value
}
$public = "https://$PublicHost"

$owner = (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
  Select-Object -First 1).OwningProcess
if ($owner) { Stop-Process -Id $owner -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }

$dshLog = Join-Path $env:TEMP "dsh-pub-$Port.log"
Remove-Item $dshLog, "$dshLog.err" -Force -ErrorAction SilentlyContinue
Start-Process -FilePath $cli `
  -ArgumentList 'web', '--host', '127.0.0.1', '--port', "$Port", '--no-open', `
    '--public-url', "$public/", '--trusted-host', $PublicHost `
  -RedirectStandardOutput $dshLog -RedirectStandardError "$dshLog.err" -WindowStyle Hidden | Out-Null

$url = $null
$deadline = (Get-Date).AddSeconds(60)
while (-not $url -and (Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 900
  $line = Get-Content $dshLog -ErrorAction SilentlyContinue |
    Select-String -Pattern 'dsh web: (http\S+)' | Select-Object -First 1
  if ($line) { $url = $line.Matches[0].Groups[1].Value }
}
if (-not $url) { throw "dsh web did not print a URL; see $dshLog.err" }

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
& node $js $QrModule $url $png | Out-Null

Write-Host "public   : $url"
Write-Host "QR image : $png"
