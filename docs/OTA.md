# OTA（A/B 槽更新）

目标：系统里能下载一次更新，写到非当前槽，回读校验，切槽重启，出问题还能回到原槽。

## 现状（2026-11-24 真机实测，OPD2513 / ColorOS 17.0.1）

| 项 | 实测值 | 含义 |
|---|---|---|
| `update_engine` | init.svc `running`，pid 1513 | 服务在，不用另起 |
| `update_engine_client` | 存在，带 `--switch_slot` 与 **`--oplus_switch_slot`** | 切槽不用自己实现 bootctrl，也没有 `bootctl` 二进制 |
| super 元数据 | `10.2` / `virtual_ab_device` / metadata 3 份 | 虚拟 A/B，两个槽都在这一个 20 GiB 分区里 |
| 槽位布局 | 13 个逻辑分区 × 2 槽，A 写在 `super 2048..19659408`，B 在 `19660800..39318160` | B 槽当前是全零占位 |
| 槽总量 | 每槽 19,647,512 sectors = 9.37 GiB，A/B 完全对称 | 一个槽塞得下 |
| `ro.boot.slot_suffix` | `_a` | 现在从 A 启动 |
| `ro.boot.veritymode` | `disabled`，`flash.locked=0` | B 槽写什么都不会被 AVB 拦，这条路才成立 |
| root | 无（`su` 不存在） | 写 `/dev/block/by-name/super` 必须先恢复 root（ReSukiSU 重装） |
| payload 工具 | 本机与仓库内都没有 `delta_generator` / `payload_generator` | 标准 OTA 的前置缺口 |
| `otacerts.zip` | 软链到 `/my_engineering/etc/security/` | 走标准 OTA 就得自造证书并重建 my_engineering |

## 两条路线

| | A：标准 AOSP payload | B：直接写 B 槽（选定） |
|---|---|---|
| 需要什么 | `delta_generator` + 自签证书 + 改 otacerts + `--update` | LP 布局 + `dd` 写扇区 + `--switch_slot` |
| 格式 | `payload.bin`（CrAU，按逻辑分区做 op） | 分区镜像文件（我们自己的产物，原样写） |
| 签名/校验 | RSA 签名，update_engine 验 otacerts | 不需要签名；用 sha256 回读校验 |
| 好处 | 标准、能做增量（bsdiff 级别）、以后能更新 boot/vbmeta | 现在就能做，零新增依赖，A 槽原样保留可回滚 |
| 代价 | 工具链缺、证书要换、payload 要按 20 GiB 布局生成 | 非标准格式；boot/dtbo/vbmeta 这类非动态分区要单独处理 |

选 B 不是偷懒：这台设备的 `veritymode=disabled`，B 槽内容本来就不校验，标准 OTA 的签名校验反而是唯一需要跨过的门槛；
而 B 路线的每一步都能用现有产物验证（我们的 parts 就是 `lpmake` 按文件大小分配的，镜像尺寸与 metadata 严格相等）。

## 工具（已落地）

```bash
# 设备侧只读勘察，不需要 root
adb shell lpdump /dev/block/by-name/super > lpdump.txt
python3 tools/ota/lp_layout.py lpdump.txt --json lp.json --slot b

# 生成设备端写入/校验脚本（--parts-dir 指向 current/parts）
python3 tools/ota/slot_writer.py lp.json --slot b --parts-dir "$GK3_PARTS" --out ota/
```

- `tools/ota/lp_layout.py`：解析 `lpdump`，输出分区 / 区间 / 组 / 快照状态 JSON；实测得到 13+13 个分区、A/B 9.37 GiB 对称。
- `tools/ota/slot_writer.py`：按 metadata 生成 `write_b.sh`（`dd bs=512 seek=… conv=notrunc` 只写 B 区间）、
  `verify_b.sh`（逐分区回读算 sha256）、`ota-manifest.json`（名字/区间/字节/sha）。尺寸与 metadata 不符会直接 FAIL。
- `tools/ota/testdata/`：真机 `lpdump` 输出与解析结果，CI 里做回归。

## 阶段计划

**S0（已完成）**：只读勘察 + 布局解析 + 写入脚本生成（dry-run 通过）。

**S1 最小分区试写**（验收：改的是 B、A 不受影响、切槽能启动）
1. 重装 ReSukiSU 拿到 root。
2. `adb push` 最小分区（`my_manifest_b`，1400 sectors = 700 KiB）到 `/data/local/tmp/gk3-ota/b/`。
3. 跑 `write_b.sh` 里对应一行 → `verify_b.sh` 回读 sha 一致。
4. `update_engine_client --switch_slot true`（先看它的返回与 `/misc` 里 bootctrl 状态），重启确认 `slot_suffix=_b`。
5. 再 `--switch_slot false` 回 A，确认 A 仍能起。**这一步只为了证明“切槽可控”，不写满 B。**

**S2 全量写入**（验收：B 槽与本次构建逐分区 sha 一致，从 B 启动后已知功能项不掉）
- 需要 `/data` 至少 10 GiB 空闲（13 个镜像 9.37 GiB）。
- 写 9.37 GiB + 回读校验 9.37 GiB，NVMe 上百秒级；中途断电不影响 A。
- 从 B 启动后按 `docs/DEVICE-TEST-CHECKLIST.md` 抽查：开机时间、密度 320、充电图标、控制中心尺寸、Wi-Fi。

**S3 打包与分发**
- 包内容：13 个分区镜像 + `ota-manifest.json` + 两个脚本，打成 `ota-<ver>.tar.zst`（分片上传，复用 `inputs` 那套）。
- 客户端按分区 sha 比对“已装 manifest”，**只下变化的**（system/odm 每次重建，其余多数不变）。
- 断点续传 + 空间预检 + 校验失败即中止。

**S4 系统内入口**
- v43 精简删掉了 `Cota` / OTA / RomUpdate 入口 APK，`update_engine` 与 boot control 还在。
- 先做一个最小入口（自建 Activity 或恢复原 APK），串起“下载→校验→写 B→切槽→重启”；
- 回滚提示：切槽后首次开机若失败，`--switch_slot false` 回 A（要有可点的入口或 adb 指令说明）。

## 风险与护栏

- **写 `super` 需要 root**，且写的是要启动的分区：脚本只碰 `*_b` 扇区，A 槽区间硬编码来自 metadata，写错范围等于毁系统。
  护栏：`slot_writer.py` 用 metadata 的区间生成脚本，不接受手写扇区；`verify_b.sh` 逐分区回读。
- **`--oplus_switch_slot` 语义未验证**：是“仅标记下一次启动”，还是连 bootctrl 一起改，S1 第 4 步要实测（看返回、看 `/misc`、看重启后的 `slot_suffix`）。
- **`/data` 空间**：写 10 GiB 镜像前先 `df`；不够就分批（一次只写变更分区）。
- **boot / dtbo / vbmeta 不在 super 里**：本路线只更新动态分区。以后要更新内核就走安装器或另做 `boot_b` 直写，别混进这条流程。
