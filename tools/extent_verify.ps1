# 只读：算 super 里某个 extent 的 sha256，用来独立校验 raw_extent_write.ps1 的写入结果。
#   powershell -File verify_extent.ps1 -Sector 2048 -Bytes 1137397760
param(
    [UInt64]$Sector = 2048,
    [UInt64]$Bytes = 1137397760
)
$ErrorActionPreference = "Stop"
$Chunk = 1MB

$sup = $null
foreach ($d in Get-Disk) {
    if ($d.PartitionStyle -ne 'GPT') { continue }
    foreach ($p in Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue) {
        if ($p.Size -eq 21474836480) { $sup = @{ Disk = $d.Number; Offset = [UInt64]$p.Offset } }
    }
}
if (-not $sup) { throw "no 20 GiB super partition found" }
$abs = $sup.Offset + $Sector * 512
Write-Output ("extent abs {0} (0x{1:X}) len {2} B" -f $abs, $abs, $Bytes)

$fs = [System.IO.FileStream]::new("\\.\PhysicalDrive$($sup.Disk)",
    [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
    [System.IO.FileShare]::ReadWrite, 1048576, [System.IO.FileOptions]::SequentialScan)
$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $buf = New-Object byte[] $Chunk
    $off = [UInt64]0
    while ($off -lt $Bytes) {
        $len = [Math]::Min([UInt64]$Chunk, $Bytes - $off)
        $fs.Position = $abs + $off
        $got = 0
        while ($got -lt $len) {
            $n = $fs.Read($buf, $got, $len - $got)
            if ($n -le 0) { throw "read ended early at $($off + $got)" }
            $got += $n
        }
        [void]$sha.TransformBlock($buf, 0, [int]$len, $null, 0)
        $off += $len
    }
    [void]$sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
    Write-Output ("sha256=" + ([BitConverter]::ToString($sha.Hash) -replace '-', '').ToLower())
} finally { $fs.Close(); $sha.Dispose() }
