param(
  [switch]$Once,
  [int]$IntervalSeconds = 2
)
$ErrorActionPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $PSScriptRoot
$ProgressFile = Join-Path $Root 'reports\progress.json'

function Read-Progress {
  if (-not (Test-Path -LiteralPath $ProgressFile)) {
    return [pscustomobject]@{
      step = 'waiting'
      percent = 0
      message = 'No progress file yet'
      updated_at = ''
      note = ''
    }
  }
  try {
    return Get-Content -LiteralPath $ProgressFile -Raw | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      step = 'invalid-state'
      percent = 0
      message = 'progress.json is being updated'
      updated_at = ''
      note = ''
    }
  }
}

function Show-Status {
  $p = Read-Progress
  $percent = [Math]::Max(0, [Math]::Min(100, [int]$p.percent))
  $width = 30
  $filled = [int]($percent / 100 * $width)
  $bar = ('#' * $filled).PadRight($width, '-')
  Write-Host ''
  Write-Host 'ColorOS -> gaokun3' -ForegroundColor Cyan
  Write-Host ('[' + $bar + '] ' + $percent + '%') -ForegroundColor Yellow
  Write-Host ('Step:    ' + $p.step)
  Write-Host ('Message: ' + $p.message)
  if ($p.updated_at) { Write-Host ('Updated: ' + $p.updated_at) }
  if ($p.note) { Write-Host ('Note:    ' + $p.note) -ForegroundColor DarkGray }
  Write-Host ''
}

if ($Once) {
  Show-Status
  exit 0
}

while ($true) {
  Clear-Host
  Show-Status
  Start-Sleep -Seconds $IntervalSeconds
}
