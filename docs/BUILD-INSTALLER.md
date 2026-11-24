# 构建安装器

安装器是 **Flutter Windows 应用 + C 后端**，两条工具链分居两个系统，所以必须由 Windows 侧编排、WSL 侧交叉编后端。
安装器源码已整棵放在 `installer/app/`（不依赖外部仓库，见 `installer/UPSTREAM.md`），一条命令跑完：

```powershell
git clone https://github.com/ArchChen1/gaokun-coloros.git
cd gaokun-coloros
.\build.ps1 -Target doctor        # 先看缺什么
.\build.ps1 -Target installer
```

## 前置

| 依赖 | 用途 | 获取 |
|---|---|---|
| WSL2 + Ubuntu 24.04 | 后端起交叉编译 | `wsl --install -d Ubuntu-24.04` |
| llvm-mingw 20261104 ucrt | 把后端编成 Windows x64/ARM64 | 脚本自动下载（sha256 钉死 `919380403de…70926`） |
| clang / make | 后端主机单测（ASan/UBSan） | `sudo make deps` / `apt install clang make` |
| Flutter 3.47.2 | Windows runner | 脚本可在缺失时下载到 `C:\flutter`（约 1 GB） |
| VS2022 + “使用 C++ 的桌面开发” | Flutter Windows 编译必需 | 微软官网安装器 |
| python3 | 拉字体（`installer/common/tool/fetch-fonts.py`） | 系统自带 |

`-SkipFlutterDownload` 可禁止脚本自动装 Flutter。

## 脚本做了什么

`build.ps1 -Target installer` 等价于 CI（`.github/workflows/ego-installer-x64.yml`）的本地版：

1. **WSL**：确认/下载 llvm-mingw → `make -C installer/app/backend test`（主机单测）
2. **WSL**：`make -C installer/app/backend win-x64 sdboot GK3W_VERSION=dev-<sha>` → `gk3w.exe`、`systemd-bootaa64.efi`
3. **WSL**：`bash installer/app/backend/mke2fs/build.sh x64` → `mke2fs.exe`、`mke2fs.conf`（Debian 源码 + 补丁）
4. **Windows**：拉字体 → `flutter pub get` → `flutter build windows --release --dart-define=GK3_VERSION=dev-<sha>`
5. 校验 Release 目录里五个必需文件都在（`gk3_windows.exe`、`backend\{gk3w.exe,mke2fs.exe,mke2fs.conf,systemd-bootaa64.efi}`）

产物：`installer/app/windows/build/windows/x64/runner/Release`

## ARM64（原生平板），在 CI 里

上游 `installer-windows.yml` 用 `windows-11-arm` 运行器出原生 ARM64。
私有仓库拿不到 ARM 运行器，所以另有一条 `ego-installer-x64.yml` 出 x64（平板上由 WoA 的 x64 模拟跑）。
要做原生 ARM64：仓库转公开或给组织开 ARM 运行器。

## 补丁在哪
安装器侧的两条改动已包含在 `installer/app`（复制自 `685c842`）：
- `GK3W_SUPER_MIB` 12288 → **20480**
- 启动项标题改 `ColorOS 17.0.1`
补丁原文另存在 `installer/patches/`（供 rebase 参考）。

## 常见问题

| 现象 | 原因 |
|---|---|
| `Release 缺 backend\gk3w.exe` | 后端产物没被 Flutter 阶段复制；先确认第 2、3 步成功，再重跑 `flutter build` |
| `mke2fs/build.sh` 失败 | 它要拉 Debian e2fsprogs 源码并打 `patches/e2fsprogs`，需要网络 |
| Flutter 报找不到 VS | 装 VS2022 时勾“使用 C++ 的桌面开发” |
| 想只编后端 | `wsl make -C installer/app/backend win-x64` |
