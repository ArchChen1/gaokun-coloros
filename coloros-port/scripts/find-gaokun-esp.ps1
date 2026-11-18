# Read-only search for the gaokun3 ESP and its systemd-boot entries.
$ErrorActionPreference = "Stop"
$dist = Get-Disk | Sort-Object Number
$found = @()
$mountedLetters = @()
foreach ($d in $dist) {
  $parts = Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Where-Object {
    $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -or $_.Type -eq 'System'
  }
  foreach ($p in $parts) {
    $letter = $null
    if ($p.DriveLetter) { $letter = "$($p.DriveLetter):" }
    else {
      $letter = "Q:"
      $used = (Get-PSDrive -Name Q -ErrorAction SilentlyContinue)
      if ($used) { Write-Host "Q: is already in use; skip disk $($d.Number) partition $($p.PartitionNumber)" -ForegroundColor Yellow; continue }
      & mountvol Q: /S 2>$null | Out-Null
      Start-Sleep -Milliseconds 400
      $vol = Get-Volume -DriveLetter Q -ErrorAction SilentlyContinue
      if (-not $vol -or $vol.FileSystem -ne 'FAT32') { & mountvol Q: /D 2>$null | Out-Null; continue }
      $mountedLetters += 'Q:'
    }
    $root = "$letter\"
    $drv = $null
    for ($i=0; $i -lt 20; $i++) {
      $drv = Get-PSDrive -Name $letter.Substring(0,1) -ErrorAction SilentlyContinue
      if ($drv) { break }
      Start-Sleep -Milliseconds 250
    }
    $entries = @()
    $entries += Get-ChildItem -LiteralPath "$root" -Recurse -File -Filter '*.conf' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'loader[\/]entries' }
    $gaokunFiles = @()
    $gaokunFiles += Get-ChildItem -LiteralPath "$root" -Recurse -File -Filter 'gaokun3.dtb' -ErrorAction SilentlyContinue
    $bootImgs = @()
    $bootImgs += Get-ChildItem -LiteralPath "$root" -Recurse -File -Filter 'ramdisk.img' -ErrorAction SilentlyContinue
    if ($entries.Count -or $gaokunFiles.Count -or $bootImgs.Count) {
      $found += [pscustomobject]@{
        Disk = $d.Number
        Partition = $p.PartitionNumber
        Letter = $letter
        GptName = $p.GptName
        Entries = ($entries.FullName -join '; ')
        Dtb = ($gaokunFiles.FullName -join '; ')
        Ramdisk = ($bootImgs.FullName -join '; ')
      }
    }
    if ($letter -eq 'Q:') { & mountvol Q: /D 2>$null | Out-Null }
  }
}
if ($found.Count -eq 0) { Write-Host 'No gaokun3 ESP found.' -ForegroundColor Red; exit 1 }
$found | Format-List
