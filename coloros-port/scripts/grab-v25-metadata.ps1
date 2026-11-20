$ErrorActionPreference = "Stop"
$out = "D:\cos\metadata-v25.img"
$offset = 343933976576
$size = 33554432
$disk = Get-Disk 0
$p = $disk | Get-Partition | Where-Object { $_.Offset -eq $offset }
if (-not $p) { throw "metadata partition not found" }
$src = "\\.\PhysicalDrive0"
$fs = [IO.File]::Open($src,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
try {
  $fs.Seek($offset,[IO.SeekOrigin]::Begin) | Out-Null
  $dst = [IO.File]::Create($out)
  try {
    $buf = New-Object byte[] (1024*1024)
    $remaining = $size
    while ($remaining -gt 0) {
      $n = $fs.Read($buf,0,[Math]::Min($buf.Length,$remaining))
      if ($n -le 0) { throw "unexpected EOF" }
      $dst.Write($buf,0,$n)
      $remaining -= $n
    }
  } finally { $dst.Dispose() }
} finally { $fs.Dispose() }
Get-Item $out | Select-Object Name,Length,LastWriteTime
Get-FileHash $out -Algorithm SHA256 | Select-Object Path,Hash