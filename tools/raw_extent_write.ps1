# 通用：把任意镜像原位写回 super 里某个逻辑分区的一段 extent（不改 lpmake 元数据）。
# 默认只校验 + 备份；真正写盘要加 -Write。回滚用 -Restore。
#
# 例：写 my_engineering_a（super 内 sector 19652608，656 sectors）
#   powershell -File raw_extent_write.ps1 -Sector 19652608 -Bytes 335872 `
#       -Image C:\gk3work\x.img -Backup C:\gk3work\x.bak -Write
param(
    [string]$Image,
    [string]$Backup,
    [UInt64]$Sector,
    [UInt64]$Bytes,
    [string]$ExpectHead1K = "",
    [switch]$Write,
    [switch]$Restore
)

$ErrorActionPreference = "Stop"
$Sec = 512
$Chunk = 1MB

function Get-SuperPartition {
    foreach ($d in Get-Disk) {
        if ($d.PartitionStyle -ne 'GPT') { continue }
        foreach ($p in Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue) {
            if ($p.Size -eq 21474836480) { return @{ Disk = $d.Number; Offset = [UInt64]$p.Offset; Num = $p.PartitionNumber } }
        }
    }
    throw "no 20 GiB super partition found"
}

function Open-Disk([int]$n) {
    return [System.IO.FileStream]::new("\\.\PhysicalDrive$n",
        [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None, 1048576, [System.IO.FileOptions]::WriteThrough)
}

function Read-At($fs, [UInt64]$pos, [int]$len) {
    $buf = New-Object byte[] $len
    $fs.Position = $pos
    $read = 0
    while ($read -lt $len) {
        $n = $fs.Read($buf, $read, $len - $read)
        if ($n -le 0) { throw "read ended early at $($pos + $read)" }
        $read += $n
    }
    return $buf
}

function Hash-Bytes($bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    return ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-', '').ToLower()
}

function Hash-File([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }

$sup = Get-SuperPartition
$abs = $sup.Offset + $Sector * $Sec
Write-Output ("super: disk {0} part {1} offset {2}; extent abs {3} (0x{4:X}) len {5} B" -f $sup.Disk, $sup.Num, $sup.Offset, $abs, $abs, $Bytes)

$src = if ($Restore) { $Backup } else { $Image }
if (-not (Test-Path -LiteralPath $src)) { throw "image missing: $src" }
if ((Get-Item -LiteralPath $src).Length -ne $Bytes) { throw "image size != $Bytes" }

$fs = Open-Disk $sup.Disk
try {
    $head = Read-At $fs $abs 1024
    $headSha = Hash-Bytes $head
    $magic = Read-At $fs ($abs + 1024) 4
    if (-not ($magic[0] -eq 0xe2 -and $magic[1] -eq 0xe1 -and $magic[2] -eq 0xf5 -and $magic[3] -eq 0xe0)) {
        throw "offset check failed: no erofs magic at +1024"
    }
    if ($Restore) {
        Write-Output "restore mode: skip current head check"
    } elseif ($ExpectHead1K -and $headSha -ne $ExpectHead1K) {
        throw "unexpected on-device head: $headSha (expected $ExpectHead1K)"
    } else {
        Write-Output "offset check OK (erofs magic, head sha256=$headSha)"
    }

    if (-not $Restore -and (Test-Path -LiteralPath $Backup)) {
        Write-Output "backup exists, skip: $Backup"
    } elseif (-not $Restore) {
        $bfs = [System.IO.File]::Create($Backup)
        $off = [UInt64]0
        while ($off -lt $Bytes) {
            $len = [Math]::Min([UInt64]$Chunk, $Bytes - $off)
            $b = Read-At $fs ($abs + $off) $len
            $bfs.Write($b, 0, $len)
            $off += $len
        }
        $bfs.Flush(); $bfs.Close()
        Write-Output ("backup: {0} B sha256={1}" -f (Get-Item $Backup).Length, (Hash-File $Backup))
    }

    if (-not $Write -and -not $Restore) {
        Write-Output "dry run only (add -Write)"
    } else {
        $ifs = [System.IO.File]::OpenRead($src)
        $off = [UInt64]0
        $buf = New-Object byte[] $Chunk
        while ($off -lt $Bytes) {
            $len = [Math]::Min([UInt64]$Chunk, $Bytes - $off)
            $n = $ifs.Read($buf, 0, $len)
            if ($n -ne $len) { throw "short read at $off" }
            $fs.Position = $abs + $off
            $fs.Write($buf, 0, $len)
            $off += $len
        }
        $ifs.Close(); $fs.Flush()
        # Verify by readback in 1 MB chunks (never load the whole extent into memory:
        # a 1 GiB extent would cost 2 GB of managed memory). Keep the ctor on a single
        # line: Windows PowerShell 5.1 rejects a line break inside ::new( ... ).
        $ifs2 = [System.IO.FileStream]::new($src, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read, 1048576)
        if ($null -eq $ifs2) { throw "cannot reopen image for readback: $src" }
        $shaR = [System.Security.Cryptography.SHA256]::Create()
        $off = [UInt64]0
        $bad = 0
        while ($off -lt $Bytes) {
            $len = [Math]::Min([UInt64]$Chunk, $Bytes - $off)
            $a = Read-At $fs ($abs + $off) ([int]$len)
            $b = New-Object byte[] ([int]$len)
            $n = $ifs2.Read($b, 0, [int]$len)
            if ($n -ne $len) { throw "short read at $off" }
            # compare per-chunk SHA256: a per-byte PowerShell loop over 1 GiB takes
            # minutes, hashing costs a few hundred ms per MB.
            $ha = $shaR.ComputeHash($a)
            $hb = $shaR.ComputeHash($b)
            if ([BitConverter]::ToString($ha) -ne [BitConverter]::ToString($hb)) { $bad++ }
            $off += $len
        }
        $shaR.Dispose()
        $ifs2.Close()
        if ($bad -ne 0) { throw "readback mismatch: $bad chunks differ" }
        Write-Output ("readback full extent matches chunk-by-chunk ({0} B, chunk {1} B)" -f $Bytes, $Chunk)
    }
} finally { $fs.Close() }
Write-Output "OK"
