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
| `installer/` | 安装器的本项目层：`UPSTREAM.md`（来源与同步）、`patches/`、`tools/make_release.py`；源码在 `vendor/gaokun-android/` |
| `tools/` | 辅助工具：`otatools/bin/lpmake`、依赖闭包求解、设备端探针脚本 |
| `releases/` | 出包产物（不入库） |
| `work/` | 抓包、截图、临时数据（不入库，只保留 `manifest.json` 快照） |

## 快速开始

```powershell
git clone https://github.com/ArchChen1/gaokun-coloros.git
cd gaokun-coloros
.\build.ps1 -Target doctor              # 环境自检
.\build.ps1 -Target deps                # WSL 侧依赖
.\build.ps1 -Target system -Version v54 # 系统镜像：parts + pack
.\build.ps1 -Target installer          # 安装器：后端(WSL 交叉编) + Flutter(Windows)
.\build.ps1 -Target all -Version v54    # 两条线一起
```

系统镜像也可以在 WSL 里直接用 make：

```bash
sudo make deps && make fetch && make verify && make parts VERSION=v54 && make pack
```

安装器的前置（Flutter 3.47.2、VS2022 C++、llvm-mingw）见 `docs/BUILD-INSTALLER.md`。

产物：`$GK3_STATE/release/super-v54.img`（附 `super.img` 软链）与 `$GK3_PUBLISH/super.img` + sha256。
默认 `GK3_WORKDIR=$HOME/gk3-build`，可用 `~/.config/gk3-coloros/env` 指到已有目录，详见 `docs/BUILD-FROM-SCRATCH.md`。

## 硬规矩

1. **出包只走 `current_pack.sh`**：它内部先跑 `current_verify.sh`，断言不过就 `PACK_ABORTED`，不会产出镜像。
2. **vendor 只从 `v52/vendor_a_v52.img` 派生**：那份带黑屏修复（turnip `queueCount` 1→2 + `debug.hwui.renderer=skiavk`）。
3. **不手写分区表**：分区清单来自 `manifest.json`。
4. **改补丁先改树/改 parts，再 `current_build.sh`**；不许临时拼基座。
5. **sha256 三处一致**：`manifest.json`、`latest/super.img.sha256.txt`、汇报里。
6. 超过 5 分钟的构建先报批准。

### 补丁不许再丢（2026-11-26 追加，已落到脚本里）

7. **账本自证**：`current_pack.sh` 与 `tools/ota/make_payload.py --manifest` 都会逐分区核对
   `bytes` + `sha256`，不符就 `PART_SHA_MISMATCH` 退出。出包/出 payload/发布都只认账本。
8. **payload 只吃账本**：`make_payload.py` 必须给 `--manifest`；`--parts` 目录模式仅供调试，会打警告。
9. **产物位置**：分区产物的唯一合法位置是 `current/parts/`（或 `builds/<版本>/`）。`work/` 是临时目录，
   永远不能当来源——本轮 system 补丁版就只躺在 `work/` 里，my_engineering 的证书版甚至没落盘。
10. **`vNN` 不是版本号**：`v52` 只有 `my_product` / `my_stock` / `vendor` 三个分区，它是**补丁层**不是「全套」；
    版本只有一个说法，就是 `manifest.json`。
11. **改分区 = 改账本**：动过哪个分区，就更新 `manifest.json` 的 sha，并在 `docs/BUILD-CURRENT.md` 事故台账记一行。
12. **新补丁不写脚本不许上机**：任何对分区的改动，先落成 `build/patches/p_*.sh`（自带「输入 sha 白名单 + 输出内容核对」），
    跑通 `bash build/patches/verify_all.sh` 再出包。没有脚本的补丁 = 下次必丢。
13. **验内容不验字节**：ext4/EROFS 重建做不到字节一致（superblock 时间戳、mkfs 版本），所以脚本核对的是文件树；
    账本里的 sha 是**设备实证产物**的 sha，别用重建产物去覆盖它。
14. **内核补丁层同样有账本**：`patches/kernel-build/kernel-artifact.json` 钉住内核树 HEAD、提交数、`.config` sha、
    `vmlinuz.efi` sha、ESP 三件套 sha；`kernel-files.lock.json` 钉住补丁改过的 136 个文件内容；
    `kernel-7.2.9-gaokun3-combined.patch` 是能重建整层的合并补丁。动内核（打补丁/改 config/重新编译）之后，
    必须重导这三件 + 上新机验证 + 更新账本，再跑 `bash build/patches/verify_kernel.sh`（要证明可重建就加 `REPLAY=1`）。

## 当前状态（2026-11-26）

- 真机：super 已改为 **legacy A/B 双槽实体分区**（20 GiB 里 A 10,059,526,144 B + B 同尺寸），
  `boot_a`/`boot_b` 重打成同一个内核（`selinux=permissive`），两槽都能独立启动。
- **OTA 端到端已打通**：自签 payload（9.37 GiB，13 分区）→ `update_engine` 下载/验签 → 写目标槽 →
  重建元数据 → 改 BCAB 切槽 → 重启进新槽 → `markBootSuccessful`（`tries 6→1`）。
  legacy A/B 没有 `--merge`（那是 VABC 的）。
- 发布清理已做（撤 `gk3run` root runner、`gk3clean`、`/metadata` 转储钩子、`ro.virtual_ab.*`、`snapuserd -ublk`），
  **并且已经用真实升级内容上机**：清理版 system `185b4991…` 打成 13 分区全量 payload，从 A 槽 OTA 到 B 槽，
  重启 `slot_suffix=_b`、`boot_completed=1`，跑在 B 的是无 root 通道的发布版。
  两槽现在故意不同源：**B = 发布版，A = 调试版（`gk3run` 还在，作 root 回退通道）**。
  主账本 `manifest.json` 的 system 已切到 `185b4991…`。
- 引导项已改名：gk3boot 两条 = `ColorOS 17 - slot A/B`，直连两条 = `Direct boot (rescue) - slot _a/_b`。
- 补丁已全部脚本化并可自证：`build/patches/{p_vendor_c2.sh,p_my_engineering_otacerts.sh,verify_all.sh}` +
  `verify_kernel.sh` 一条命令跑五层（分区账本 / 关键 sha / 补丁内容含发布清理 / 反向检查 / 内核引导三件套），
  当前 `VERIFY_ALL_PASSED`。
- 未完成：原厂「软件更新」UI 复刻、App 端 `applyPayload`、A 槽也升级到发布版（会失去 root 通道，需先决定调试手段）。
  已核实：`markSuccessful` 在 legacy A/B 下生效（BCAB `b` 由 `tries6/ok0` 变 `tries1/ok1`），默认启动回发布版 B。
  进 A 槽必须用 gk3boot 的 `Direct boot (rescue) - slot _a`；菜单里的 `ColorOS 17 - slot A` 是走 BCAB 的条目，不强制槽位。

详见 `docs/ARCHITECTURE.md`、`docs/BUILD-CURRENT.md`、`docs/INCIDENTS.md`。
