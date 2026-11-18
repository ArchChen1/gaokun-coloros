param(
  [string]$OutDir = "C:\gk3-pstore"
)
$ErrorActionPreference = "Stop"

$source = @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class EfiPstoreNative {
    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern uint GetNextVariableName(ref uint size, StringBuilder name, ref Guid guid);

    [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern uint GetFirmwareEnvironmentVariableW(
        string name, string guid, IntPtr buffer, uint size);

    public static Guid CrashGuid = new Guid("cfc8fc79-be2c-4dd1-9bd9-6b8da13c8b8f");
}
"@
Add-Type -TypeDefinition $source

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$found = 0
$guid = [Guid]::Empty
$size = 1024
$name = New-Object System.Text.StringBuilder 1024

while ($true) {
    $size = $name.Capacity
    $ok = [EfiPstoreNative]::GetNextVariableName([ref]$size, $name, [ref]$guid)
    if ($ok -eq 0) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        if ($err -eq 259) { break }
        if ($err -eq 122) {
            $newCapacity = [Math]::Max(1024, $size + 128)
            $name = New-Object System.Text.StringBuilder $newCapacity
            $size = $newCapacity
            continue
        }
        throw "GetNextVariableName failed: Win32 error $err"
    }

    $varName = $name.ToString()
    if ($varName -like 'dump-type*') {
        $found++
        $needed = [EfiPstoreNative]::GetFirmwareEnvironmentVariableW(
            $varName,
            "{cfc8fc79-be2c-4dd1-9bd9-6b8da13c8b8f}",
            [IntPtr]::Zero,
            0)
        if ($needed -eq 0) {
            $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            if ($err -ne 122) { Write-Warning "Cannot size $varName (error $err)"; continue }
        }

        $buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal([int]$needed)
        try {
            $got = [EfiPstoreNative]::GetFirmwareEnvironmentVariableW(
                $varName,
                "{cfc8fc79-be2c-4dd1-9bd9-6b8da13c8b8f}",
                $buffer,
                $needed)
            if ($got -eq 0) {
                $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Warning "Read $varName failed (error $err)"
                continue
            }
            $bytes = New-Object byte[] $got
            [Runtime.InteropServices.Marshal]::Copy($buffer, $bytes, 0, $got)
            $safe = $varName -replace '[^A-Za-z0-9._-]', '_'
            $path = Join-Path $OutDir "$safe.bin"
            [IO.File]::WriteAllBytes($path, $bytes)
            Write-Host "WROTE $path ($got bytes)"
        } finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
        }
    }

    $name.Clear() | Out-Null
}

if ($found -eq 0) {
    Write-Host "No pstore variables were found." -ForegroundColor Yellow
    Write-Host "Check that efi_pstore.pstore_disable=1 is removed from the boot options,"
    Write-Host "androidboot.init_fatal_panic=true is present, and the failed boot has happened once."
} else {
    Write-Host "Exported $found pstore record(s) to $OutDir" -ForegroundColor Green
}
