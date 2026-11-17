param(
  [switch]$Once,
  [int]$IntervalSeconds = 2
)

$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $PSScriptRoot

function Get-WslSnapshot {
  $bash = @'
set -u
ROOT=/mnt/e/gaokun-coloros/coloros-port
SPARSE=/home/cenmin/coloros-build/sparse
BUILD=/home/cenmin/coloros-build
echo "sparse_count=$(find "$SPARSE" -maxdepth 1 -name '*.img' 2>/dev/null | wc -l)"
echo "sparse_bytes=$(du -sb "$SPARSE" 2>/dev/null | awk '{print $1}')"
echo "extract_dirs=$(find /home/cenmin/coloros-trees-xattr -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
echo "super_bytes=$(stat -c %s "$BUILD/super.img" 2>/dev/null || echo 0)"
echo "super_zst_bytes=$(stat -c %s "$BUILD/super.img.zst" 2>/dev/null || echo 0)"
echo "process=$(ps -eo cmd | grep -E 'lpmake|img2simg|fsck.erofs|mkfs.erofs|zstd|payload_extract' | grep -v grep | head -1)"
echo "free_gb=$(df -BG / | awk 'NR==2 {gsub(/G/,"",$4); print $4}')"
echo "latest=$(find "$BUILD" -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %p\n' 2>/dev/null | sort | tail -1)"
echo "ota_bytes=$(stat -c %s "$ROOT/inputs/OPD2513_17.0.1.200.zip" 2>/dev/null || echo 0)"
echo "raw_parts=$(find "$ROOT/work/opd2513" -maxdepth 1 -name '*.img' 2>/dev/null | wc -l)"
'@

  $raw = & wsl.exe -d Ubuntu-24.04 -u root -- bash -lc $bash 2>$null
  $map = @{}
  foreach ($line in $raw) {
    if ($line -match '^([^=]+)=(.*)$') {
      $map[$matches[1]] = $matches[2]
    }
  }
  return $map
}

function To-GB([string]$bytes) {
  if (-not $bytes) { return '0.0' }
  return ([double]$bytes / 1GB).ToString('0.0')
}

function Get-Stage($s) {
  $super = [long]($s.super_bytes ?? 0)
  $sparseCount = [int]($s.sparse_count ?? 0)
  $extractDirs = [int]($s.extract_dirs ?? 0)
  $rawParts = [int]($s.raw_parts ?? 0)

  if ($super -ge 12884901888) { return @{ Name = 'super generated'; Pct = 90 } }
  if ($super -gt 0) { return @{ Name = 'generating super'; Pct = 80 } }
  if ($sparseCount -ge 13) { return @{ Name = 'sparse ready, starting super'; Pct = 65 } }
  if ($sparseCount -gt 0 -or $extractDirs -ge 8) { return @{ Name = 'converting partitions to sparse'; Pct = 30 + [Math]::Min(30, $sparseCount * 2) } }
  if ($rawParts -gt 0) { return @{ Name = 'extracting ColorOS partitions'; Pct = 15 } }
  return @{ Name = 'preparing donor'; Pct = 5 }
}

function Show-Snapshot {
  $s = Get-WslSnapshot
  $stage = Get-Stage $s
  $barWidth = 28
  $filled = [Math]::Max(0, [Math]::Min($barWidth, [int]([double]$stage.Pct / 100 * $barWidth)))
  $bar = ('#' * $filled).PadRight($barWidth, '-')

  Write-Host ''
  Write-Host 'ColorOS -> gaokun3  build status' -ForegroundColor Cyan
  Write-Host ('Time: ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
  Write-Host ("Stage: [{0}] {1}%  {2}" -f $bar, $stage.Pct, $stage.Name) -ForegroundColor Yellow
  Write-Host ''
  Write-Host ("ColorOS OTA     : {0} GB" -f (To-GB $s.ota_bytes))
  Write-Host ("Raw partitions  : {0} files" -f $s.raw_parts)
  Write-Host ("Extracted trees : {0} dirs" -f $s.extract_dirs)
  Write-Host ("Sparse parts    : {0} files, {1} GB" -f $s.sparse_count, (To-GB $s.sparse_bytes))
  Write-Host ("Formal super    : {0} GB" -f (To-GB $s.super_bytes))
  Write-Host ("Compressed super: {0} GB" -f (To-GB $s.super_zst_bytes))
  Write-Host ("WSL free space  : {0} GB" -f $s.free_gb)
  if ($s.process) {
    Write-Host ("Current process : {0}" -f $s.process) -ForegroundColor Green
  } else {
    Write-Host 'Current process : idle' -ForegroundColor DarkGray
  }
  if ($s.latest) {
    Write-Host ("Latest file     : {0}" -f $s.latest)
  }
  Write-Host ''
  Write-Host 'Note: no device write happens during this build.' -ForegroundColor DarkGray
}

if ($Once) {
  Show-Snapshot
  exit 0
}

while ($true) {
  Clear-Host
  Show-Snapshot
  Start-Sleep -Seconds $IntervalSeconds
}
