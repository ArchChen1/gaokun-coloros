param(
    [string]$Image  = "C:\gk3work\vendor_c2.img",
    [string]$Backup = "C:\gk3work\vendor_a_backup.img",
    [string]$ExpectCurrent4M = "48197eb2e6f4169abdd0d6d45a549c493304b6fc4a6b652e842638b0c69edaa5",
    [switch]$Write,
    [switch]$Restore
)

# ASCII-only script (avoid codepage parser issues over ssh).
# Writes vendor_a extent in place: super partition offset + 4478976 sectors.
$ErrorActionPreference = "Stop"
$ExtentSector = 4478976
$ExtentBytes  = 536870912
$Sec          = 512
$Chunk        = 8MB

function Get-SuperPartition {
    foreach ($d in Get-Disk) {
        if ($d.PartitionStyle -ne 'GPT') { continue }
        foreach ($p in Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue) {
            if ($p.Size -eq 21474836480) { return @{ Disk = $d.Number; Offset = [UInt64]$p.Offset; Num = $p.PartitionNumber } }
        }
    }
    Write-Output "==== partition table"
    foreach ($d in Get-Disk) {
        Write-Output ("disk {0}: {1} {2} {3} B" -f $d.Number, $d.FriendlyName, $d.PartitionStyle, $d.Size)
        foreach ($p in Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue) {
            Write-Output ("  part {0}: offset {1} size {2} type '{3}' letter {4}" -f $p.PartitionNumber, $p.Offset, $p.Size, $p.Type, $p.DriveLetter)
        }
    }
    throw "no 20 GiB (21474836480 B) super partition found"
}

function Open-Disk([int]$n) {
    return [System.IO.FileStream]::new("\\.\PhysicalDrive$n",
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::ReadWrite,
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

function Hash-File([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}

$sup = Get-SuperPartition
$abs = $sup.Offset + [UInt64]$ExtentSector * $Sec
Write-Output ("super: disk {0} part {1} offset {2} (0x{3:X})" -f $sup.Disk, $sup.Num, $sup.Offset, $sup.Offset)
Write-Output ("vendor_a abs offset {0} (0x{1:X}) len {2} B" -f $abs, $abs, $ExtentBytes)

$src = if ($Restore) { $Backup } else { $Image }
if (-not (Test-Path -LiteralPath $src)) { throw "image missing: $src" }
if ((Get-Item -LiteralPath $src).Length -ne $ExtentBytes) { throw "image size mismatch" }
$srcSha = Hash-File $src
Write-Output "source: $src sha256=$srcSha"

$fs = Open-Disk $sup.Disk
try {
    $probe = Read-At $fs $abs 4MB
    $probeSha = Hash-Bytes $probe
    if ($probe[1080] -ne 0x53 -or $probe[1081] -ne 0xEF) { throw "first 4 MiB is not ext4 superblock" }
    if ($Restore) {
        Write-Output "restore mode: skip current-state check"
    } elseif ($probeSha -ne $ExpectCurrent4M) {
        throw "unexpected on-device content: probe=$probeSha, expected $ExpectCurrent4M"
    } else {
        Write-Output "offset check OK (on-device first 4 MiB == base image, sha256=$probeSha)"
    }

    if (-not $Restore) {
        if (Test-Path -LiteralPath $Backup) {
            Write-Output "backup exists, skip: $Backup"
        } else {
            Write-Output "dumping vendor_a -> $Backup"
            $bfs = [System.IO.File]::Create($Backup)
            $off = [UInt64]0
            while ($off -lt $ExtentBytes) {
                $len = [Math]::Min([UInt64]$Chunk, $ExtentBytes - $off)
                $b = Read-At $fs ($abs + $off) $len
                $bfs.Write($b, 0, $len)
                $off += $len
            }
            $bfs.Flush(); $bfs.Close()
            Write-Output ("backup done: {0} B sha256={1}" -f (Get-Item -LiteralPath $Backup).Length, (Hash-File $Backup))
        }
    }

    if (-not $Write -and -not $Restore) {
        Write-Output "dry run only (add -Write)"
    } else {
        Write-Output "writing $ExtentBytes B ..."
        $ifs = [System.IO.File]::OpenRead($src)
        $off = [UInt64]0
        $buf = New-Object byte[] $Chunk
        while ($off -lt $ExtentBytes) {
            $len = [Math]::Min([UInt64]$Chunk, $ExtentBytes - $off)
            $n = $ifs.Read($buf, 0, $len)
            if ($n -ne $len) { throw "short read from image at $off" }
            $fs.Position = $abs + $off
            $fs.Write($buf, 0, $len)
            $off += $len
        }
        $ifs.Close()
        $fs.Flush()
        Write-Output "written, reading back ..."
        $readSha = Hash-Bytes (Read-At $fs $abs 67108864)
        $headFull = New-Object byte[] 67108864
        $fh2 = [System.IO.File]::OpenRead($src); [void]$fh2.Read($headFull, 0, 67108864); $fh2.Close()
        if ($readSha -ne (Hash-Bytes $headFull)) { throw "readback mismatch (first 64 MiB)" }
        Write-Output "readback first 64 MiB matches"
    }
} finally { $fs.Close() }
Write-Output "OK"
