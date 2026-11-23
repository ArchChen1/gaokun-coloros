# gaokun-coloros

华为 MateBook E Go（OPD2513 / gaokun3 / SC8280XP）的 **ColorOS 17.0.1 移植工作区**。
目标不是“能开机一次”，而是可长期维护、可远程推更新的发行版：安装器、20 GiB 双槽 super、OTA/update_engine。

本仓库是唯一工作区。旧的 `E:\gaokun-coloros`（68 GB，历史脚本与抓包堆在一个没有提交的树里）已退役，
只作为素材来源保留。**新的构建链、断言、文档都在这里。**

## 目录

| 路径 | 内容 |
|---|---|
| `build/` | 构建流水线：`current_verify.sh`（断言闸门）、`current_build.sh`（固化基座 + 重打 system/odm）、`current_pack.sh`（出 super + 发布）、`current_cleanup.sh`（清盘） |
| `build/legacy/` | 历史脚本（v51 vendor 补丁、v52d/v52e 分区脚本、v52 super 脚本），只作参考，不再执行 |
| `docs/` | 架构、构建规范、事故台账、刷机与验收清单 |
| `docs/releases/` | 历史发布说明与专项报告（v43 系列、v45） |
| `patches/` | 具体补丁及其说明（SystemUI 充电、vendor 黑屏修复说明等） |
| `installer/` | 安装器派生层：上游补丁（`patches/`）、发布自检工具（`tools/make_release.py`） |
| `tools/` | 辅助工具：`otatools/bin/lpmake`、依赖闭包求解、设备端探针脚本 |
| `releases/` | 出包产物（不入库） |
| `work/` | 抓包、截图、临时数据（不入库，只保留 `manifest.json` 快照） |

## 快速开始

```powershell
# 1. 断言当前基座（必须全绿）
wsl -u root -d Ubuntu-24.04 -- bash /mnt/e/gk3-coloros/build/current_verify.sh

# 2. 固化基座并重打 system / odm（改过树之后跑）
wsl -u root -d Ubuntu-24.04 -- bash /mnt/e/gk3-coloros/build/current_build.sh

# 3. 出包并发布到 Windows 侧
wsl -u root -d Ubuntu-24.04 -- bash /mnt/e/gk3-coloros/build/current_pack.sh
```

产物：`D:\gaokun-coloros-release\latest\`（`super.img`、`super.img.sha256.txt`、`boot.img`、`install-artifacts.sha256`），
HTTP 上在 `http://192.168.1.152:8001/latest/`。

前置：构建机是 WSL Ubuntu-24.04，基座目录 `/home/cenmin/coloros-build/current/`（分区产物 + `manifest.json` + `logs/`）。

## 硬规矩

1. **出包只走 `current_pack.sh`**：它内部先跑 `current_verify.sh`，断言不过就 `PACK_ABORTED`，不会产出镜像。
2. **vendor 只从 `v52/vendor_a_v52.img` 派生**：那份带黑屏修复（turnip `queueCount` 1→2 + `debug.hwui.renderer=skiavk`）。
3. **不手写分区表**：分区清单来自 `manifest.json`。
4. **改补丁先改树/改 parts，再 `current_build.sh`**；不许临时拼基座。
5. **sha256 三处一致**：`manifest.json`、`latest/super.img.sha256.txt`、汇报里。
6. 超过 5 分钟的构建先报批准。

## 当前状态（2026-11-24）

- 已在真机跑通的镜像：进桌面正常、控制中心/侧边栏尺寸一致（密度 320 由 rc 的属性触发维持，不再需要外部脚本）。
- 开机：`boot_progress_start` 16.8 s、`enable_screen` 46.7 s（此前 78.7 s / 104.8 s，ath11k 固件时序问题已修）。
- 未完成：充电图标 —— `oplus_charger_hal_service` 仍缺两个库（`android.hardware.sensors-V3-ndk.so`、`libhidltransport.so`），需进 `odm/lib64`。
- 未开始：系统更新入口（`Cota`/OTA 相关 APK 在 v43 精简时被删）、OTA 整包、正式发版形态（`super.img.zst` + `boot.img` + sha + 全量 OTA）。

详见 `docs/ARCHITECTURE.md`、`docs/BUILD-CURRENT.md`、`docs/INCIDENTS.md`。
