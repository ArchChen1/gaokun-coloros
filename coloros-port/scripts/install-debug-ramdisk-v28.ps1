param(
  [string]$DebugRamdisk = 'D:\cos\ramdisk-capture.img',
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $DebugRamdisk)) { throw "debug ramdisk not found: $DebugRamdisk" }
$debugHash = (Get-FileHash -LiteralPath $DebugRamdisk -Algorithm SHA256).Hash.ToLower()
Write-Host "debug ramdisk: $DebugRamdisk"
Write-Host "sha256: $debugHash"

$mountedHere = $false
if (-not (Test-Path X:\)) {
  mountvol X: /S | Out-Null
  Start-Sleep -Milliseconds 800
  $mountedHere = $true
}
$ramdisks = @(Get-ChildItem -LiteralPath 'X:\' -Recurse -File -Filter 'ramdisk.img' -ErrorAction SilentlyContinue)
if ($ramdisks.Count -eq 0) { throw 'No ramdisk.img found on ESP' }
$ramdisks | Select-Object FullName,Length | Format-Table -AutoSize
if (-not $Apply) {
  Write-Host 'Dry run only. Add -Apply to replace ramdisk.img and keep .before-v28-debug backups.' -ForegroundColor Yellow
  if ($mountedHere) { mountvol X: /D | Out-Null }
  exit 0
}
foreach ($r in $ramdisks) {
  $backup = "$($r.FullName).before-v28-debug"
  if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $r.FullName -Destination $backup }
  Copy-Item -LiteralPath $DebugRamdisk -Destination $r.FullName -Force
  $actual = (Get-FileHash -LiteralPath $r.FullName -Algorithm SHA256).Hash.ToLower()
  if ($actual -ne $debugHash) { throw "verification failed for $($r.FullName): $actual" }
  Write-Host "replaced and verified: $($r.FullName)" -ForegroundColor Green
}
if ($mountedHere) { mountvol X: /D | Out-Null }
Write-Host 'Done. Logs will be under ESP \gk3-debug.' -ForegroundColor Cyan
