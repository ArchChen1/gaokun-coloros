param(
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$mountedHere = $false

if (-not (Test-Path X:\)) {
  & mountvol X: /S | Out-Null
  Start-Sleep -Milliseconds 800
  $mountedHere = $true
}

function Set-OptionToken {
  param([string]$Text, [string]$Name, [string]$Value)
  $linePattern = '(?m)^(\s*options\s+)(.*?)(\r?\n|$)'
  $m = [regex]::Match($Text, $linePattern)
  if (-not $m.Success) { throw 'options line not found' }
  $opts = $m.Groups[2].Value
  $tokenPattern = '(?i)(^|\s)' + [regex]::Escape($Name) + '=\S+'
  if ([regex]::IsMatch($opts, $tokenPattern)) {
    $opts = [regex]::Replace($opts, $tokenPattern, '${1}' + $Name + '=' + $Value)
  } else {
    $opts = ($opts.TrimEnd() + ' ' + $Name + '=' + $Value).Trim()
  }
  $newLine = $m.Groups[1].Value + $opts + $m.Groups[3].Value
  return $Text.Substring(0, $m.Index) + $newLine + $Text.Substring($m.Index + $m.Length)
}

try {
  $entries = @(Get-ChildItem -LiteralPath 'X:\loader\entries' -File -Filter '*-android-*.conf' -ErrorAction SilentlyContinue)
  if ($entries.Count -lt 1) {
    throw 'No Android entries found under X:\loader\entries. Run the installer first, then rerun this script.'
  }

  foreach ($e in $entries) {
    $text = [IO.File]::ReadAllText($e.FullName)
    $new = Set-OptionToken -Text $text -Name 'androidboot.selinux' -Value 'permissive'
    $new = Set-OptionToken -Text $new -Name 'loglevel' -Value '7'

    if ($new -notmatch 'androidboot\.selinux=permissive') { throw "selinux verify failed: $($e.FullName)" }
    if ($new -notmatch '(?i)(^|\s)loglevel=7(\s|$)') { throw "loglevel verify failed: $($e.FullName)" }

    if ($DryRun) {
      Write-Host "DRY RUN $($e.FullName)" -ForegroundColor Yellow
    } else {
      $backup = $e.FullName + '.before-permissive-v38r2'
      if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $e.FullName -Destination $backup -Force
      }
      [IO.File]::WriteAllText($e.FullName, $new, [Text.UTF8Encoding]::new($false))
      $check = [IO.File]::ReadAllText($e.FullName)
      if ($check -notmatch 'androidboot\.selinux=permissive') { throw "post-write selinux verify failed: $($e.FullName)" }
      if ($check -notmatch '(?i)(^|\s)loglevel=7(\s|$)') { throw "post-write loglevel verify failed: $($e.FullName)" }
      Write-Host "OK $($e.FullName)" -ForegroundColor Green
    }
    Get-Content -LiteralPath $e.FullName | Select-String -Pattern '^options\s'
  }
} finally {
  if ($mountedHere) { & mountvol X: /D | Out-Null }
}