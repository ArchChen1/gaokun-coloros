# 用 Android SDK build-tools 直接编 updater/，不依赖 Gradle。
#   powershell -File build/updater_build.ps1
# 产物：work/updater-build/gk3-ota.apk（已签名，包名 com.oplus.ota）
param(
    [string]$Sdk = "D:\Android\Sdk",
    [string]$BuildTools = "35.0.0",
    [string]$Platform = "android-35"
)

$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $Repo "updater"
$Work = Join-Path $Repo "work\updater-build"
$Bt = Join-Path $Sdk "build-tools\$BuildTools"
$Jar = Join-Path $Sdk "platforms\$Platform\android.jar"
$Ks = Join-Path $Src "keystore\gk3-ota.jks"
$KsPass = "gk3ota"

foreach ($p in @($Jar, (Join-Path $Bt "aapt2.exe"), (Join-Path $Bt "d8.bat"), (Join-Path $Bt "zipalign.exe"), (Join-Path $Bt "apksigner.bat"))) {
    if (-not (Test-Path $p)) { throw "缺工具: $p" }
}

Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$Work\classes", "$Work\dex", "$Work\gen", (Join-Path $Src "keystore") | Out-Null

Write-Host "== 1/6 编译资源"
& "$Bt\aapt2.exe" compile --dir (Join-Path $Src "res") -o "$Work\res.zip"
if ($LASTEXITCODE -ne 0) { throw "aapt2 compile 失败" }

Write-Host "== 2/6 链接资源与清单"
& "$Bt\aapt2.exe" link -o "$Work\unsigned.apk" -I $Jar `
    --manifest (Join-Path $Src "AndroidManifest.xml") `
    --min-sdk-version 30 --target-sdk-version 34 `
    --java "$Work\gen" `
    -A (Join-Path $Src "assets") `
    "$Work\res.zip"
if ($LASTEXITCODE -ne 0) { throw "aapt2 link 失败" }

Write-Host "== 3/6 编译 Java"
$JdkBin = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME "bin" } else { "C:\Program Files\Zulu\zulu-25\bin" }
if (-not (Test-Path $JdkBin)) { throw "找不到 JDK：$JdkBin（设 JAVA_HOME）" }
$env:JAVA_HOME = Split-Path $JdkBin -Parent
$env:PATH = "$JdkBin;$env:PATH"
$Javac = Join-Path $JdkBin "javac.exe"
$sources = @(Get-ChildItem -Path (Join-Path $Src "src") -Recurse -Filter *.java | ForEach-Object { $_.FullName })
$sources += @(Get-ChildItem -Path "$Work\gen" -Recurse -Filter *.java | ForEach-Object { $_.FullName })
& $Javac --release 8 -nowarn -cp $Jar -d "$Work\classes" $sources
if ($LASTEXITCODE -ne 0) { throw "javac 失败" }

Write-Host "== 4/6 dex"
& "$Bt\d8.bat" --min-api 30 --lib $Jar --output "$Work\dex" (Get-ChildItem -Path "$Work\classes" -Recurse -Filter *.class | ForEach-Object { $_.FullName })
if ($LASTEXITCODE -ne 0) { throw "d8 失败" }

Write-Host "== 5/6 装 dex 并对齐"
$py = @'
import sys, zipfile, os
work = sys.argv[1]
apk = os.path.join(work, "unsigned.apk")
with zipfile.ZipFile(apk, "a", zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(work, "dex", "classes.dex"), "classes.dex")
print("classes.dex 已写入")
'@
$py | python - $Work
if ($LASTEXITCODE -ne 0) { throw "写 dex 失败" }
& "$Bt\zipalign.exe" -f 4 "$Work\unsigned.apk" "$Work\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "zipalign 失败" }

Write-Host "== 6/6 签名"
if (-not (Test-Path $Ks)) {
    $Keytool = Join-Path (Split-Path (Get-Command java).Source -Parent) "keytool.exe"
    & $Keytool -genkeypair -keystore $Ks -storepass $KsPass -keypass $KsPass `
        -alias gk3ota -keyalg RSA -keysize 2048 -validity 10950 -dname "CN=GK3 OTA, O=gaokun-coloros" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "生成 keystore 失败" }
}
& "$Bt\apksigner.bat" sign --ks $Ks --ks-pass "pass:$KsPass" --key-pass "pass:$KsPass" `
    --out "$Work\gk3-ota.apk" "$Work\aligned.apk"
if ($LASTEXITCODE -ne 0) { throw "apksigner 失败" }

$size = (Get-Item "$Work\gk3-ota.apk").Length
Write-Host ("OK  {0}  ({1:N0} B)" -f "$Work\gk3-ota.apk", $size)
