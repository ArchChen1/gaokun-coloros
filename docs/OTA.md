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
| root | 已恢复（ReSukiSU 重装，`uid=0` / `ksu` 域） | 写 `/dev/block/by-name/super` 靠它 |
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

## 工具（已落地，全部真机跑通）

```bash
# 设备侧只读勘察，不需要 root
adb shell lpdump /dev/block/by-name/super > lpdump.txt
python3 tools/ota/lp_layout.py lpdump.txt --json lp.json --slot b

# 生成设备端脚本（--parts-dir 指向 current/parts；--only 可只挑几个分区小步试写）
bash build/ota_stage.sh --slot b          # 收镜像 + 调 slot_writer，产物在 $GK3_WORKDIR/ota/
```

- `tools/ota/lp_layout.py`：解析 `lpdump`，输出分区 / 区间 / 组 / 快照状态 JSON；实测得到 13+13 个分区、A/B 9.37 GiB 对称。
- `tools/ota/slot_writer.py`：按 metadata 生成 `write_b.sh`（`dd bs=512 seek=… conv=notrunc` 只写 B 区间）、
  `verify_b.sh`（逐分区回读算 sha256，失败 `exit 1`）、`apply_b.sh`（源镜像 sha → 写 → 回读 → 可选切槽）、
  `rollback.sh`（切回另一槽）、`ota-manifest.json`（名字/区间/字节/sha）。尺寸与 metadata 不符会直接 FAIL。
- `build/ota_stage.sh`：把 `current/parts` 与 `src` 的 13 个镜像收进一个 staging 目录再调 `slot_writer`，
  免得每次手敲文件名。注意 Windows 侧 `adb.exe` 读不了 WSL 的软链，推镜像要直接用真实源路径。
- `tools/ota/testdata/`：真机 `lpdump` 输出与解析结果，CI 里做回归。

设备端用法（`/data/local/tmp/gk3-ota/` 下）：

```bash
su -c 'sh /data/local/tmp/gk3-ota/apply_b.sh'          # 只写+校验，不切槽
su -c 'sh /data/local/tmp/gk3-ota/apply_b.sh switch'   # 校验通过后切到 B
su -c 'sh /data/local/tmp/gk3-ota/rollback.sh'         # 从 B 切回 A（同一条命令来回切）
```

## 阶段计划

**S0（已完成）**：只读勘察 + 布局解析 + 写入脚本生成（dry-run 通过）。

**S1 / S2（已完成，2026-11-24 真机跑通）**

1. root 恢复后按 `tools/ota/testdata/lp-layout.json` 生成 13 个分区的写入/回读脚本。
2. 13 个镜像 9.37 GiB 推到 `/data/local/tmp/gk3-ota/b/`（Wi-Fi adb，23–32 MB/s，约 7 分钟）。
3. `write_b.sh` 写入 170 s，`verify_b.sh` 回读 9.37 GiB 算 sha 27 s，**13/13 分区 OK**。
4. `update_engine_client --oplus_switch_slot=true` → 重启 → `ro.boot.slot_suffix=_b`，30 s 连上，
   `sys.boot_completed=1`，密度 320/320，设置页正常渲染（截图见会话记录）。
5. 在 B 上再跑一次 `--oplus_switch_slot=true` → 重启 → 回 `_a`。**来回切两趟都成功，A 槽内容从未被改。**
6. 一条 `apply_b.sh` 从“源镜像 sha 校验”走到“回读校验”，全程 198 s，输出 `APPLY_OK`。

**切槽的真实语义（实测，别再猜）**

- `--oplus_switch_slot=true` 是**切换开关**：在 A 上执行就进 B，在 B 上执行就回 A。不需要 `=false`。
- `--switch_slot=true`（标准那个）这台机器上用不了：它要先读 `/data/ota_package/metadata`，没这文件直接
  `Status(-8): '23: Failed to open /data/ota_package/metadata'`，`/misc` 一个字节都不动。
- 切换只改 `/misc` 的 bootctrl 块：实测字节差 6 个 —— `0x80C`（`9f→9e`）、`0x80E`（`00→6f`，切回时 `9f`）
  以及 `0x81C..0x81F` 的 CRC32。`0x810` 的 `_a` 字段不随之变，所以它不是“当前槽位”。
- 应急回滚：开机进 A 后 `dd` 把切换前的 4 KiB `/misc` 快照写回去，重启即回 A（已验证一次）。
  这条只当保险，正常路径还是走 `rollback.sh`。

**S3 打包与分发**（下一步）
- 包内容：13 个分区镜像 + `ota-manifest.json` + 脚本，打成 `ota-<ver>.tar.zst`（分片上传，复用 `inputs` 那套）。
- 客户端按分区 sha 比对“已装 manifest”，**只下变化的**（system/odm 每次重建，其余多数不变）。
- 断点续传 + 空间预检 + 校验失败即中止。

**S4 系统内入口**
- v43 精简删掉了 `Cota` / OTA / RomUpdate 入口 APK，`update_engine` 与 boot control 还在。
- 先做一个最小入口（自建 Activity 或恢复原 APK），串起“下载→校验→写 B→切槽→重启”；
- 回滚提示：切槽后首次开机若失败，跑一次 `--oplus_switch_slot=true` 就回另一槽（要有可点的入口或 adb 指令说明）。

## 风险与护栏

- **写 `super` 需要 root**，且写的是要启动的分区：脚本只碰 `*_b` 扇区，A 槽区间来自 metadata，写错范围等于毁系统。
  护栏：`slot_writer.py` 用 metadata 的区间生成脚本，不接受手写扇区；`verify_b.sh` 逐分区回读。
- **切槽不校验目标槽内容**：`--oplus_switch_slot` 无条件切，B 写坏了它照样切过去。所以 `apply_b.sh` 把
  “回读校验通过”卡在切槽之前，校验失败就 `exit 1` 不切。
- **`/data` 空间**：写 9.37 GiB 镜像前先 `df`；不够就分批（一次只写变更分区，`--only` 支持）。
- **`boot` / `dtbo` / `vbmeta` 不在 super 里**：本路线只更新动态分区。实测 `boot_a` 与 `boot_b` 当前 sha 相同
  （`aaaeb1b5…ffe8`，安装器两槽都刷了），所以切 B 能起；以后换内核必须同步刷 `boot_b`，别混进这条流程。
- **B 槽 odm 缺充电 HAL 的两个 so**（`libhidltransport.so`、`android.hardware.sensors-V3-ndk.so`）：
  B 上 `oplus_charger_hal_service` 同样在 `restarting`，与 A 一致 —— 说明 `odm.erofs` 还没重打，是独立待办。

