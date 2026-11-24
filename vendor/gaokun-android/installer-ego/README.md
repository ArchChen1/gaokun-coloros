# EGO 安装器（基于上游 vahiru/gaokun-android）

本目录是「ColorOS 移植（EGO）」的安装器适配层。上游安装器本来就针对同一台机器（MateBook E Go / gaokun3），
所以适配不是重写，而是**在 upstream 上压两条最小补丁**，其余全部复用——上游更新时只需要 rebase。

- 上游仓库：<https://github.com/vahiru/gaokun-android>（GPL-3.0，含 Windows 安装器与 Live 安装器）
- 本地 vendored 副本：`E:\gaokun-coloros\third_party\gaokun-android`（浅克隆，分支 `ego-coloros`）
- 基线提交：`230fa9a Merge pull request #130 from vahiru/docs/installer`

## 为什么只需要改两处

上游安装器与我们的移植在「磁盘布局 + 启动方式」上本来就是同一套：

| 项目 | 上游 | EGO 现状 |
|---|---|---|
| 分区 | esp 300M / misc 4M / metadata 32M / boot_a,b 64M / super / userdata | 完全相同（本机就是这么装的） |
| ESP 结构 | `<machine-id>/android/slot_a|b/{Image,gaokun3.dtb,ramdisk.img>` | 本机 ESP 已有 `02a061f10c3fd2c0d21ea60430eeed67/android/slot_a/...`，同一结构 |
| boot 载体 | systemd-boot + `loader/entries/<mid>-android-a.conf` | 相同（本机 entries 就是 `crDroid 16.0 — slot _a`，由该安装器写入） |
| boot.img | v2 头，kernel + ramdisk + dtb | 本机 boot.img 已是 v2、含 170 KiB dtb、page 2048（已用工具校验通过） |
| super | 12 GiB sparse | 唯一要改：EGO 用 20 GiB（双槽 9.3 GiB × 2 + 余量） |

所以补丁只有：

1. `patches/0001-…patch`：`installer/backend/src/plan.h` 的 `GK3W_SUPER_MIB` 12288 → 20480。
2. `patches/0002-…patch`：ESP 启动项标题改为 `ColorOS 17.0.1 (alpha-v1)`（`esp.h` 的 `GK3W_EGO_TITLE`，含单测与 `check_install.py` 同步）。

## 品牌与分发策略（ColorOS 分支）

- 界面与启动项统一叫 **ColorOS**，设备名写 **gaokun3**（“EGO”只是内部叫法，不进任何用户可见产物）。
- **只做离线安装**：`boot.img`、`super.img`、`install-artifacts.sha256` 由**另一个发布仓库**分发，用户在那下载后在本机选目录安装。安装器不再从 GitHub / R2 拉版本，也不再制作 LiveCD 介质——这两条入口在 `Session.allowOnline = false` 时直接从界面隐藏（上游代码保留，打开开关即恢复，方便合并上游）。
- 图标不再用上游的 crDroid 眼睛：`installer-ego/tools/make_branding.py`（Pillow，不需要 ImageMagick）生成绿色开口圆环标记，重算 `assets/logo.png`、`windows/runner/resources/app_icon.ico`、web 图标（含 maskable）。

## 发布目录（安装器吃的产物）

```
release/
├── boot.img                  # 必选，v2 + dtb + cmdline，≤64 MiB
├── super.img.zst 或 super.img # 必选，sparse 格式；本项目默认未压缩的 super.img
└── install-artifacts.sha256  # 可选，建议有：<sha256>  <文件名>
```

- `super.img` 必须是 **sparse**（`lpmake` 带 `-S`），展开后正好 20 GiB；安装器会先整份试解一遍再动盘。
- `boot.img` 里必须有 dtb：安装器会把 kernel / dtb / ramdisk 拆出来分别写到 ESP 的 `slot_a`、`slot_b`。
  （EGO 的 boot.img 目前是含 dtb 的，校验通过；如果哪天改成"dtb 只放 ESP"，安装器就会写 0 字节 dtb，开不了机。）
- 自检工具：`tools/make_release.py`
  ```
  python tools/make_release.py --boot boot.img --check-only
  python tools/make_release.py --boot boot.img --super super.img --out release
  ```
  它按上游安装器的规则逐项检查（v2 / page size / header_size 1660 / kernel 是 PE / dtb 是 FDT / cmdline 纯 ASCII /
  super 是 sparse 且展开 20 GiB），最后生成 `install-artifacts.sha256`。

## 构建：GitHub Actions（已跑通，x64 + 原生 ARM64）

构建全部在私有仓库 `ArchChen1/ego-gaokun-installer` 的 Actions 里完成，本机不装工具链。

| 产物 | 工作流 | 运行器 | 结果 | 体积 |
|---|---|---|---|---|
| `coloros-installer-windows-x64.zip` | `ego-installer-x64.yml` | ubuntu-24.04（后端 llvm-mingw 交叉编 x64）+ windows-latest（Flutter x64） | 成功（run 45192289986） | 24.6 MB |
| `coloros-installer-windows-arm64.zip` | 上游 `installer-windows.yml`（原生 ARM64） | ubuntu-24.04（后端 aarch64）+ **windows-11-arm**（Flutter arm64） | 成功（run 45192296222） | 23.7 MB |

要点：

- **私有仓库也能用 `windows-11-arm` 运行器**（已实测：job `app (arm64)` 在 2026-11-23 13:20 拿到 runner，日志显示 `windows-11-vs2026-arm64` 镜像、`build\windows\arm64\runner\Release\gk3_windows.exe`）。所以不需要为了 CI 把仓库转公开。
- ARM64 产物是原生 arm64，不是 x64 模拟；后端 `gk3w.exe` 由 `win-arm64` 目标用 llvm-mingw 编译。
- 已发布预览：`installer-alpha-v2`（prerelease，资产 `coloros-installer-windows-x64.zip` / `-arm64.zip`），两个 zip 都挂在 release 资产里。
- 后端单测（`make test`）在 20 GiB 改动后要跟着重算固定分区与 userdata 期望值，已改为用 `GK3W_SUPER_MIB` 等宏推导，避免下次改常量再崩。

本机复核方式（只验产物形态，不动盘）：

```
python installer-ego/tools/make_release.py --boot boot.img --check-only
```

## 上游更新怎么合并

`third_party/gaokun-android` 是普通 git 仓库、`ego-coloros` 分支只多两个提交：

```
cd E:\gaokun-coloros\third_party\gaokun-android
git remote add upstream https://github.com/vahiru/gaokun-android   # 首次
git fetch --depth 1 upstream main
git rebase upstream/main
git format-patch main..ego-coloros -o ..\..\coloros-port\installer-ego\patches
```

- 冲突只会落在 `plan.h`（super 大小）与 `esp.c`（标题）；其余文件我们没动。
- 每次同步后，用 `tools/make_release.py` 再跑一遍产物自检，确认上游没改发布目录约定。
- 许可：上游 GPL-3.0，我们的分支与发布物必须继续 GPL-3.0，并公开这两条补丁（`patches/` 已满足）。

## 还没做的适配（待办）

1. **UI 文案**：Flutter 侧 `l10n` 里仍有 “crDroid”“gaokun-android” 字样（`installer/*/lib/l10n/app_*.arb`），发布前统一改成 ColorOS/EGO。
2. **发布源**：上游默认从 GitHub/自建镜像下载 `boot.img`、`super.img.zst`；EGO 需要自己的 OTA 服务器地址与 `install-artifacts.sha256` 托管。
3. **机型校验**：上游检查 `GK-W7X`，与本机一致，无需改；若要支持其它 SKU 再放宽。
4. **Live ISO**：本机没有 Docker 与 Linux 构建环境，Live 安装器暂缓；先用 Windows 安装器 + 现有 adb 流程。
5. **首次装机脚本化**：把「GPT（super 20 GiB）+ boot_a/b + super + ESP 入口」串成一条命令，作为安装器不可用时的兜底。
6. **实例化验证**：在真机上用改过常量的安装器跑一次“重装 Android（保留数据/清数据各一次）”，确认 20 GiB super 的 GPT 建立、ESP 写入、开机与 A/B 入口都正常。

## 与其它文档的关系

- 分区与精简预算：`../docs/DEBLOAT-PLAN.md`（20 GiB super、单槽 9.28 GiB 的来源）
- OTA 现状与引擎问题：`../reports/V43-OTA-STATUS-2026-11-23.md`
- 上游安装说明：`third_party/gaokun-android/docs/INSTALL.md`
