# 一站式构建入口（Windows 侧）。
#
#   .\build.ps1 -Target doctor                 # 检查环境
#   .\build.ps1 -Target deps                   # 装 WSL 侧依赖
#   .\build.ps1 -Target system -Version v54    # 系统镜像：parts + pack
#   .\build.ps1 -Target installer             # 安装器：后端(WSL 交叉编) + Flutter(Windows)
#   .\build.ps1 -Target all -Version v54       # 先系统镜像，再安装器
#
# 前置：WSL2(Ubuntu) + Flutter + VS2022 C++ 工具链 + python3。doctor 会逐项说明缺什么。
param(
  [ValidateSet('doctor','deps','system','installer','all','verify','pack','clean')]
  [string]$Target = 'doctor',
  [string]$Version = 'dev',
  [string]$Distro = 'Ubuntu-24.04',
  [switch]$ForceBackend,
  [switch]$SkipFlutterDownload
)

$ErrorActionPreference = 'Stop'
$Repo = $PSScriptRoot
$Installer = Join-Path $Repo 'vendor\gaokun-android'
$FlutterVersion = '3.47.2'
$LlmName = 'llvm-mingw-20261104-ucrt-ubuntu-22.04-x86_64'
$LlmSha = '919380403de87dca3c581c2053230cd298af5e891286628ba0613b7fed370926'

function ToWslPath([string]$p) {
  $p = $p -replace '\\', '/'
  if ($p -match '^([A-Za-z]):') { return "/mnt/$($Matches[1].ToLower())" + $p.Substring(2) }
  return $p
}
function Invoke-Wsl([string]$cmd) {
  Write-Host "  [wsl] $cmd" -ForegroundColor DarkGray
  wsl -u root -d $Distro -- bash -lc $cmd
  if ($LASTEXITCODE -ne 0) { throw "WSL 命令失败（exit $LASTEXITCODE）: $cmd" }
}
function Have([string]$exe) { return [bool](Get-Command $exe -ErrorAction SilentlyContinue) }

# ---------- doctor ----------
function Invoke-Doctor {
  Write-Host '== Windows' -ForegroundColor Cyan
  $ok = $true
  if (Have 'wsl') { Write-Host "  OK   wsl" } else { Write-Host "  FAIL wsl（需要 WSL2）"; $ok = $false }
  $dists = (wsl -l -q 2>$null) -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
  if ($dists -contains $Distro) { Write-Host "  OK   $Distro" } else { Write-Host "  FAIL 缺发行版 $Distro（wsl --install -d $Distro）"; $ok = $false }

  if (Have 'flutter') { Write-Host "  OK   flutter $((flutter --version 2>$null | Select-Object -First 1))" }
  elseif (Test-Path 'C:\flutter\bin\flutter.bat') { Write-Host '  OK   C:\flutter（未在 PATH，脚本会自己用）' }
  else { Write-Host '  FAIL flutter（https://docs.flutter.dev/get-started/install/windows）'; $ok = $false }

  $cl = Get-Command 'cl.exe' -ErrorAction SilentlyContinue
  if ($cl) { Write-Host '  OK   MSVC cl.exe' }
  elseif (Test-Path 'C:\Program Files\Microsoft Visual Studio\2022') { Write-Host '  OK   VS2022 已装（需“使用 C++ 的桌面开发”）' }
  else { Write-Host '  FAIL Visual Studio 2022 + 桌面 C++（Flutter Windows runner 必需）'; $ok = $false }

  if (Have 'python') { Write-Host '  OK   python（取字体用）' } else { Write-Host '  WARN 缺 python，installer/common/tool/fetch-fonts.py 会跳过' }

  Write-Host '== WSL' -ForegroundColor Cyan
  Invoke-Wsl "bash $(ToWslPath $Repo)/build/doctor-tools.sh"
  Write-Host ''
  if ($ok) { Write-Host 'doctor: 系统镜像可以构建；安装器看上面 flutter/VS 两项' } else { Write-Host 'doctor: 有缺项，见上' }
}

# ---------- WSL 依赖 ----------
function Invoke-Deps {
  $r = ToWslPath $Repo
  Invoke-Wsl "cd $r && make deps"
}

# ---------- 系统镜像 ----------
function Invoke-System([string]$ver, [switch]$onlyVerify, [switch]$onlyPack, [switch]$onlyClean) {
  $r = ToWslPath $Repo
  if ($onlyVerify) { Invoke-Wsl "cd $r && make verify"; return }
  if ($onlyPack)   { Invoke-Wsl "cd $r && make pack"; return }
  if ($onlyClean)  { Invoke-Wsl "cd $r && make clean"; return }
  Invoke-Wsl "cd $r && make parts VERSION=$ver && make pack"
}

# ---------- 安装器 ----------
function Ensure-llvm-mingw {
  $script = @"
set -e
D=`$HOME/opt/$LlmName
if [ ! -d "`$D" ]; then
  echo '下载 llvm-mingw'
  mkdir -p `$HOME/opt /tmp/llm
  curl -fL --retry 3 -o /tmp/llm/llm.tar.xz https://github.com/mstorsjo/llvm-mingw/releases/download/20261104/$LlmName.tar.xz
  echo '$LlmSha  /tmp/llm/llm.tar.xz' | sha256sum -c
  tar -C `$HOME/opt -xf /tmp/llm/llm.tar.xz
fi
echo 'LLVM_MINGW_OK'
"@
  Invoke-Wsl ($script -replace "`r", '')
}

function Invoke-InstallerBackend {
  if (-not (Test-Path (Join-Path $Installer 'installer\backend\Makefile'))) { throw '缺 vendor/gaokun-android/installer/backend，仓库不完整' }
  Ensure-llvm-mingw
  $sub = ToWslPath $Installer
  $v = "dev-" + (git -C $Repo rev-parse --short HEAD)
  Invoke-Wsl "cd $sub && make -C installer/backend test"
  Invoke-Wsl "cd $sub && make -C installer/backend win-x64 sdboot GK3W_VERSION=$v LLVM_MINGW=`$HOME/opt/$LlmName"
  Invoke-Wsl "cd $sub && bash installer/backend/mke2fs/build.sh x64"
  Invoke-Wsl "cd $sub && ls -l installer/backend/build/x64/gk3w.exe installer/backend/build/sdboot/systemd-bootaa64.efi"
}

function Invoke-InstallerApp {
  $flutter = if (Have 'flutter') { 'flutter' } elseif (Test-Path 'C:\flutter\bin\flutter.bat') { 'C:\flutter\bin\flutter.bat' } else { $null }
  if (-not $flutter) {
    if ($SkipFlutterDownload) { throw '缺 Flutter：装好后重跑，或去掉 -SkipFlutterDownload 让脚本下载' }
    Write-Host "  未发现 Flutter，按 CI 版本下载 $FlutterVersion 到 C:\flutter" -ForegroundColor Yellow
    git clone --quiet --depth 1 --branch $FlutterVersion https://github.com/flutter/flutter.git 'C:\flutter'
    $flutter = 'C:\flutter\bin\flutter.bat'
  }
  $win = Join-Path $Installer 'installer\windows'
  if (Have 'python') { python (Join-Path $Installer 'installer\common\tool\fetch-fonts.py') }
  Push-Location $win
  try {
    & $flutter --disable-analytics; & $flutter config --enable-windows-desktop
    & $flutter pub get
    & $flutter build windows --release "--dart-define=GK3_VERSION=dev-$(git -C $Repo rev-parse --short HEAD)"
  } finally { Pop-Location }

  $rel = Join-Path $win 'build\windows\x64\runner\Release'
  $need = @('gk3_windows.exe', 'backend\gk3w.exe', 'backend\mke2fs.exe', 'backend\mke2fs.conf', 'backend\systemd-bootaa64.efi')
  foreach ($f in $need) { if (-not (Test-Path (Join-Path $rel $f))) { throw "Release 缺 $f —— 后端产物要被阶段到 backend/（Flutter 构建会复制 assets，见 installer/windows/pubspec.yaml）" } }
  Write-Host "  OK   安装器产物: $rel" -ForegroundColor Green
  return $rel
}

switch ($Target) {
  'doctor'    { Invoke-Doctor }
  'deps'      { Invoke-Deps }
  'verify'    { Invoke-System $Version -onlyVerify }
  'pack'      { Invoke-System $Version -onlyPack }
  'clean'     { Invoke-System $Version -onlyClean }
  'system'    { Invoke-System $Version }
  'installer' { Invoke-InstallerBackend; Invoke-InstallerApp }
  'all'       { Invoke-System $Version; Invoke-InstallerBackend; Invoke-InstallerApp }
}
