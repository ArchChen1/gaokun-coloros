param(
  [string]$Adb = "E:\gaokun-coloros\analysis\coloros_port\bin\flash\platform-tools-windows\adb.exe",
  [string]$OutputRoot = "E:\gaokun-coloros\coloros-port\reports\boot-capture",
  [int]$PollMs = 700
)
$ErrorActionPreference = "SilentlyContinue"
if (-not (Test-Path -LiteralPath $Adb)) { throw "adb not found: $Adb" }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
Write-Host "Waiting for Android ADB. Keep this window open; Ctrl+C stops." -ForegroundColor Cyan
$session = 0
$lastSerial = $null
while ($true) {
  & $Adb start-server 2>$null | Out-Null
  $lines = @(& $Adb devices 2>$null)
  $online = $null
  foreach ($line in $lines) {
    $cols = @($line -split '\s+')
    if ($cols.Count -ge 2 -and $cols[1] -eq 'device') { $online = $line; break }
  }
  if (-not $online) {
    if ($lastSerial) { Write-Host "ADB disconnected; waiting for the next boot." -ForegroundColor Yellow; $lastSerial = $null }
    Start-Sleep -Milliseconds $PollMs
    continue
  }
  $serial = (@($online -split '\s+'))[0]
  $lastSerial = $serial
  $session++
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $safeSerial = $serial -replace '[^A-Za-z0-9._-]', '_'
  $dir = Join-Path $OutputRoot ("session-{0:D3}-{1}-{2}" -f $session, $stamp, $safeSerial)
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  Write-Host "ADB online: $serial -> $dir" -ForegroundColor Green

  & $Adb -s $serial shell getprop > (Join-Path $dir "getprop.txt") 2>&1
  & $Adb -s $serial shell "cat /proc/cmdline; echo; cat /proc/version; echo; getenforce" > (Join-Path $dir "boot-info.txt") 2>&1
  & $Adb -s $serial shell "ls -la /sys/fs/pstore" > (Join-Path $dir "pstore-list.txt") 2>&1
  & $Adb -s $serial exec-out "sh -c 'cat /sys/fs/pstore/* 2>/dev/null'" > (Join-Path $dir "pstore.txt") 2>&1
  & $Adb -s $serial exec-out "sh -c 'dmesg 2>&1'" > (Join-Path $dir "dmesg.txt") 2>&1
  & $Adb -s $serial exec-out "sh -c 'su -c dmesg 2>&1'" > (Join-Path $dir "dmesg-root.txt") 2>&1
  & $Adb -s $serial exec-out "sh -c 'cat /proc/last_kmsg 2>&1'" > (Join-Path $dir "last-kmsg.txt") 2>&1
  & $Adb -s $serial shell "service list" > (Join-Path $dir "services.txt") 2>&1
  & $Adb -s $serial shell "getprop sys.boot_completed" > (Join-Path $dir "boot-completed.txt") 2>&1

  $log = Join-Path $dir "logcat-all.txt"
  $err = Join-Path $dir "logcat-stderr.txt"
  $p = Start-Process -FilePath $Adb -ArgumentList @("-s", $serial, "logcat", "-b", "all", "-v", "threadtime") -RedirectStandardOutput $log -RedirectStandardError $err -PassThru -NoNewWindow
  while ($p -and -not $p.HasExited) { Start-Sleep -Seconds 1 }
  Write-Host "Session ended." -ForegroundColor Yellow
}
