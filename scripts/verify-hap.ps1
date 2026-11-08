param(
  [string]$Hap = 'E:\HarmonyOS\Projects\HelloHarmony\entry\build\default\outputs\default\entry-default-signed.hap',
  [string]$Bundle = 'com.example.helloharmony',
  [string]$Ability = 'EntryAbility'
)
$ErrorActionPreference = 'Stop'
$hdc = 'E:\HarmonyOS\DevEcoStudio\sdk\default\openharmony\toolchains\hdc.exe'

Write-Host '== hdc server ==' -ForegroundColor Cyan
& $hdc start | Out-Null

Write-Host '== waiting for emulator/device (max 180s) ==' -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds(180)
$target = $null
while ((Get-Date) -lt $deadline) {
  $t = & $hdc list targets 2>$null | Where-Object { $_ -and $_ -notmatch '\[Empty\]' }
  if ($t) { $target = $t[0]; break }
  Start-Sleep -Seconds 3
}
if (-not $target) { throw 'No device/emulator found. Start one in DevEco Device Manager first.' }
Write-Host "target: $target" -ForegroundColor Green

Write-Host '== install ==' -ForegroundColor Cyan
& $hdc -t $target install -r $Hap

Write-Host '== launch ==' -ForegroundColor Cyan
& $hdc -t $target shell aa start -a $Ability -b $Bundle
Start-Sleep -Seconds 4

Write-Host '== screenshot ==' -ForegroundColor Cyan
& $hdc -t $target shell snapshot_display -f /data/local/tmp/helloharmony.jpeg
$out = 'E:\HarmonyOS\Projects\HelloHarmony\screenshot.jpeg'
& $hdc -t $target file recv /data/local/tmp/helloharmony.jpeg $out
if (Test-Path $out) { Write-Host "screenshot: $out" -ForegroundColor Green } else { Write-Host 'screenshot failed' -ForegroundColor Yellow }

Write-Host '== process check ==' -ForegroundColor Cyan
& $hdc -t $target shell aa dump -a 2>$null | Select-Object -First 20
