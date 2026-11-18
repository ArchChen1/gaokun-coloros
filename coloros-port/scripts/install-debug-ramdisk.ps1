param(
  [string]$DebugRamdisk = "E:\gaokun-coloros\coloros-port\out\debug\ramdisk-debug.img",
  [switch]$Apply
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $DebugRamdisk)) { throw "debug ramdisk not found: $DebugRamdisk" }
$debugHash = (Get-FileHash -LiteralPath $DebugRamdisk -Algorithm SHA256).Hash.ToLower()
Write-Host "debug ramdisk: $DebugRamdisk"
Write-Host "sha256: $debugHash"

$targets = @()
foreach ($disk in Get-Disk | Sort-Object Number) {
  foreach ($part in Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue) {
    $tmp = $null
    if ($part.DriveLetter) {
      $tmp = "$($part.DriveLetter):"
    } else {
      $free = Get-Volume -DriveLetter Q -ErrorAction SilentlyContinue
      if ($free) { continue }
      mountvol Q: /S 2>$null | Out-Null
      $vol = Get-Volume -DriveLetter Q -ErrorAction SilentlyContinue
      if (-not $vol -or $vol.FileSystem -ne 'FAT32') { mountvol Q: /D 2>$null | Out-Null; continue }
      $tmp = 'Q:'
    }
    $root = "$tmp\"
    try {
      $dtbs = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'gaokun3.dtb' -ErrorAction SilentlyContinue)
      if ($dtbs.Count -gt 0) {
        $targets += [pscustomobject]@{
          Disk=$disk.Number; Part=$part.PartitionNumber; Temp=$tmp
          Dtb=($dtbs.FullName -join '; ')
          Ramdisks=(@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'ramdisk.img' -ErrorAction SilentlyContinue).FullName -join '; ')
        }
      }
    } finally {
      if ($tmp -eq 'Q:') { mountvol Q: /D 2>$null | Out-Null }
    }
  }
}
if ($targets.Count -eq 0) { throw 'No ESP containing gaokun3.dtb was found' }
$targets | Format-List
if (-not $Apply) {
  Write-Host 'Dry run only. Add -Apply to mount the gaokun ESP and replace ramdisk.img.' -ForegroundColor Yellow
  exit 0
}
if ($targets.Count -ne 1) { throw "Expected exactly one gaokun ESP, found $($targets.Count)" }
$t = $targets[0]
$hadQ = $false
if ($t.Temp -eq 'Q:') {
  if (Get-Volume -DriveLetter Q -ErrorAction SilentlyContinue) { throw 'Q: is in use' }
  mountvol Q: /S 2>$null | Out-Null
  $hadQ = $true
  Start-Sleep -Seconds 1
}
$root = "$($t.Temp)\"
$ramdisks = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter 'ramdisk.img' -ErrorAction SilentlyContinue)
if ($ramdisks.Count -eq 0) { throw 'No ramdisk.img found on the gaokun ESP' }
foreach ($r in $ramdisks) {
  $backup = "$($r.FullName).before-debug"
  if (-not (Test-Path -LiteralPath $backup)) { Copy-Item -LiteralPath $r.FullName -Destination $backup }
  Copy-Item -LiteralPath $DebugRamdisk -Destination $r.FullName -Force
  $actual = (Get-FileHash -LiteralPath $r.FullName -Algorithm SHA256).Hash.ToLower()
  if ($actual -ne $debugHash) { throw "verification failed for $($r.FullName): $actual" }
  Write-Host "replaced and verified: $($r.FullName)" -ForegroundColor Green
}
if ($hadQ) { mountvol Q: /D 2>$null | Out-Null }
Write-Host 'Done. Boot Ego and wait for reboot; logs will be on the ESP at \gk3-debug\kmsg.log.' -ForegroundColor Cyan
