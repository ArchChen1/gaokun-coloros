# 转向 legacy A/B：super 元数据重建

## 决策

放弃「单份 super + VABC 快照」作为发布形态，改为 **legacy A/B（super 内两套实体分区，更新直接覆盖另一个槽）**。

理由：

1. VABC 的 COW 只能落在 `/metadata`（物理 32 MB、可用 25.2 MiB），而整块替换 `system`（1.1 GB）
   的 COW 需要约 1 GB，物理上不可能；要补这个缺口同样得改 GPT、清 userdata。
2. VABC 依赖一串自研机制：`update_engine` 3 字节 AVB 补丁、ublk 后端、`snapuserd` 拉起、
   `ro.virtual_ab.*` 属性。每换一次 Android 基座都要重新验证。
3. legacy A/B 走官方路径（写另一槽 + `bootctl` 切槽 + 失败回滚），没有自研机制要维护。
4. 本机 super 20 GiB 中已用 10.06 GB，**空着的 10 GB 本来就是留给 B 槽的**，B 槽从未建出来。

VABC 能力不删：保留在 `docs/OTA-VABC-UBLK.md`，将来只发几十 MB 的小补丁时仍可用。

## 本机 super 元数据实际布局（实测）

```
4096    geometry 副本 1        （SHA256 校验）
8192    geometry 副本 2        （内容相同）
12288   metadata 副本 1
77824   metadata 副本 2        12288 + 1*65536
143360  metadata 副本 3        12288 + 2*65536
208896  metadata 副本 4        12288 + 3*65536
尾部    无备份元数据
```

- geometry：`metadata_max_size=65536`、`slot_count=2`、`logical_block_size=4096`
- header：version 10.2、`header_size=256`；`header_checksum` 与 `tables_checksum` **均为 SHA256**
  （不是 CRC32），表格起点 = metadata 起点 + `header_size`
- 条目大小：partition 52 / extent 24 / group 48 / block_device 64
- 原 header flags = 1（`virtual_ab_device`）

## 生成结果

工具：`tools/ota/lp_ab_meta.py`（纯 Python，无 liblp 依赖）

```
parse <head.bin>            解析 + geometry SHA256 / header SHA256 / tables SHA256 三重校验
build <head.bin> <out.bin>  生成 A/B 双槽版本
```

产物 `work/super_head_ab.bin`（1 MiB 头部区）：

- A 槽 13 个分区 **extents 完全保持原值**（`system_a` 仍在 sector 2048 起）
- B 槽 13 个分区按同尺寸分配在 sector `19660800` 起的空闲区，末尾 `39319552`
- 设备末尾 `41943040` 扇区，剩余约 2.6M 扇区（1.25 GiB）缓冲
- header flags 清为 0（不再声明 virtual A/B）
- 元数据 2440 字节（上限 65536），组 `gaokun3_dynamic_partitions_b` 一并写入

离线校验：把产物推到设备上用 `lpdump`（可解析普通文件）解析，26 个分区、双组、
`Header flags: none` 全部正常，无需写盘即可验证。

## 写回方案（尚未执行）

1. **备份**：`super` 头部 1 MiB（`/data/local/tmp/super_head.bin` + 本地 `work/super_head.bin`）。
   现有布局尾部无备份元数据，因此这是唯一原始凭证。
2. **写入**：把 `super_head_ab.bin` 写到 `super` 偏移 0（绝对 `344101748736`）。
3. **校验**：`lpdump /dev/block/by-name/super` 应显示 26 个分区；再重启确认 A 槽能正常起。
4. **回滚**：把 `super_head.bin` 写回同一偏移即可恢复原元数据。

## 后续

- B 槽镜像：设备内 `dd` 从各 A extent 复制到对应 B extent（不走网络），约 10 GB。
- `boot_b`：从 `boot_a`（`nvme0n1p8` → `nvme0n1p9`）复制。
- 切槽验证：`update_engine_client --oplus_switch_slot` → 重启进 B → 回滚 A。
- 发布镜像需删除：`gk3run`（root 后门）、`gk3clean` 的清理动作、`gk3boot` 的 `/metadata`
  转储钩子；`update_engine` 的 3 字节 AVB 补丁在 legacy A/B 下待验证是否还需要。

## 真机验证记录（2026-11-26）

### 元数据写回

- 写前备份 `super` 头 1 MiB：sha256 `2e8de985…`（原始布局唯一凭证）
- 写入 `super_head_ab.bin`（sha `aa3e25d9…`），回读 sha 一致
- 写后 `lpdump` 读真盘：`Header flags: none`、元数据 2440 B、26 个分区、3 个组；
  A 槽 13 条 extents 与写前逐条一致
- 重启后 A 槽正常启动（`sys.boot_completed=1`、`slot_suffix=_a`），
  init 一次建立 26 个 dm-linear（13 个 `_a` + 13 个 `_b`）

### B 槽内容

- dm 设备由分区 `readonly` 属性建成只读，**不能**用 `dd` 写 `mapper/*_b`
  （`write error: Operation not permitted`）；必须直接写 `super` 块设备的 B extent
- A、B 两套布局的间隙完全同形（B = A 平移 19,658,752 扇区），可整段一次拷：
  `dd if=super of=super bs=1M skip=1 seek=9600 count=9598` + 尾部 1856 扇区补 512 B
- 10,064,232,448 B / 24 s（约 394 MB/s）
- 校验：13 个分区 `mapper/*_a` 与 `*_b` 整盘 sha256 全部一致

### 引导与切槽

- `boot_b` 从 `boot_a` 复制，sha `3e39ac63…` 双方一致
- ESP `476f1043…/android/slot_b/` 原为 11-24 的旧内核（18.7 MB），已对齐成
  `slot_a` 那份（Image sha `db5a1aa1…`、ramdisk sha `9cbc5339…`），原件备份在
  `/data/local/tmp/esp_slot_b_bak/`
- ESP 已存在 `slot_b` 目录 ⇒ 切槽不需要动 ESP 结构，只要槽内内容与 misc 状态对
- `update_engine_client --oplus_switch_slot` **不会**切槽：只把当前槽 `tries` 5→6；
  `--switch_slot=true` 需要 `/data/ota_package/metadata`，不是纯切槽入口
- 实际选槽由 `gk3boot` 按 misc BCAB 的 priority 决定（`core/src/bcab.c`
  `gk3_select_slot`），菜单手选只在 BCAB 无效时作为 hint
- 写盘前实测 BCAB 就是「B 槽 priority 15 / tries 5 / 未成功，A 槽 priority 14 / 已成功」，
  即出厂早把 B 标成下一个启动槽，只是 B 一直没内容 ⇒ 不需要改 misc 就能切到 B

### B 槽启动（通过）

- 菜单选 slot b 重启：`ro.boot.slot_suffix=_b`、`sys.boot_completed=1`
- 挂载全部来自 `dm-14…dm-25`（`_b` 设备），`system_a`/`system_b` sha 均为 `4011db1d…`
- 启动后 BCAB：`slot_b pri=15 tries=1 ok=1`、`slot_a pri=14 tries=1 ok=1`
  ⇒ `gk3boot` 扣 tries 与 Android `markBootSuccessful` 都正常工作

## 引导条目拓扑（ESP 上 6 项）

```
loader.conf: timeout 5 / default *-android-a.conf

476f1043…-android-a.conf   Direct boot (rescue) - slot _a   直连：linux=ESP slot_a/Image
476f1043…-android-b.conf   Direct boot (rescue) - slot _b   直连：linux=ESP slot_b/Image
gk3boot-android-a.conf     ColorOS 17 - slot A  gk3.hint=a  走 gk3boot → 读 misc 选槽
gk3boot-android-b.conf     ColorOS 17 - slot B  gk3.hint=b
gk3boot-tools.conf         Android fastboot / boot menu
EFI/Microsoft/Boot         Windows
```

（标题在一次轮换后会带后缀：`.staged`/观察模式为 `ColorOS 17 - slot A (observe)`，被替换下来的旧版为
`ColorOS 17 - slot A (prev loader)`。命名统一在 `installer/backend/src/esp.c`、`Gk3Boot.cpp:EntryText`、
`gaokun3-ota-postinstall.sh:gk3_entry_text` 三处，测试断言同步在 `installer/backend/test/linux/check_install.py`、
`tools/gk3boot/test/{hal,postinstall}/run.sh`。2026-11-26 已把这六项在盘上改名完毕。）

- 直连条目把内核/ramdisk/dtb 全写在 ESP 上，`androidboot.slot_suffix` 写死在 options 里
- gk3boot 条目不指定内核，它自己读 `boot_<x>` 分区 + 追加 `androidboot.slot_suffix`
- `gk3.hint` 只在 BCAB 无效时生效（`gk3boot.c:41`、`core/src/bcab.c:174-177`）；
  BCAB 有效时按 priority 挑「可启动」的槽，`gk3.fbtcp`/`gk3.slot` 是另一套（测试用强制槽）

## 真机踩到的坑：boot 分区里是失效镜像

现象：选 gk3boot 条目（无论 hint a/b）→ 起几秒自动重启；选直连条目正常。

日志（`EFI/gk3boot/log/boot-13.txt`）给出了完整链条：

```
bcab: valid  _a=14/1/ok  _b=15/0/unbootable
decision: boot slot=_a active=_b fallback=1
boot_a: p8 v2 kernel=18743808 ramdisk=13468543 dtb=174904 id=f768786d…
cmdline.base(584): …androidboot.selinux=enforcing…
```

- 选槽逻辑没错：B 不可启动 → 正确回落 A 并记 `fallback`
- 但回落用的 `boot_a` 里是 11-24 的旧 boot v2 镜像（kernel 18,743,808 / ramdisk 13,468,543），
  和 ESP `slot_a` 那份（Image 16,134,656 / ramdisk 13,145,568，sha `db5a1aa1…` / `9cbc5339…`）不是一套
- 旧镜像 cmdline 是 `androidboot.selinux=enforcing`，本系统在 enforcing 下起不来 ⇒ 秒级自重启

修法：用 ESP 三件套重打 boot v2 镜像写进 `boot_a`/`boot_b`，让两条路径启动同一个内核。

### 打包工具 `tools/ota/bootimg_v2.py`

- id 规则（`core/src/bootimg.c:10`、`:85-100`）：
  `id[0:20] = SHA1(kernel‖le32(kernel_size), ramdisk‖le32(ramdisk_size),
   second‖le32(second_size), [recovery_dtbo‖le32(len)], [dtb‖le32(len))])`
  —— 每段后面连一个 4 字节 LE 长度，不是裸拼。用原 boot_a 复算，id 完全对上（`f768786d…`）
- base cmdline 拼接（`core/src/cmdline.c:92-102`）：`cmdline[512] + extra_cmdline[1024]` **直接相连**，
  所以超过 512 字节的部分要放进 `extra_cmdline`，不能截断
- 其它字段按原镜像抄：page 2048、v2、header_size 1660、os_version `0x220001aa`、
  kernel/ramdisk/tags/dtb 地址、`selinux=permissive` 的 596 字符 cmdline
- 产物 `work/boot_ab.img` 29,460,480 B，sha `0dae44bb…`，写入 `boot_a`/`boot_b` 后回读 sha 一致

### 两个方向的验证

| 场景 | BCAB | 结果 |
|------|------|------|
| 回滚（B 不可启动） | `a:14/1/1` `b:15/0/0` | `slot=_a`、`event=fallback`、`selinux=permissive`、开机完成 |
| 正常切槽 | `a:14/1/1` `b:15/7/0` | `slot=_b`、`event=none`、开机完成，misc 变 `b:15/1/1` |

`misc` 的工具是 `tools/ota/bcab_edit.py`（CRC 用 `zlib.crc32(前 28 字节)`，与 `core/src/util.c:82` 等价，
已用真机数据验证过 `stored == calc`）。

## 发布清理（2026-11-26 已做）

镜像树 `/home/cenmin/v50-build/system` 相对基座的差异，现在只剩白名单里这几项（`build/rebuild_system_patched.sh` 的 `ALLOW`）：

| 项 | 处理 | 理由 |
|---|---|---|
| `system/etc/init/snapuserd.rc` 的 `gk3run` service | 删 | 它就是 root 后门：`setprop ctl.start gk3run` 即以 root 跑 `/data/local/tmp/gk3run.sh`，production build 默认没有 `su`，谁都能借它提权 |
| 同文件的 `gk3clean` + `on boot start gk3clean` | 删 | 开机清 `/metadata` 的调试卫生，发布版没有转储，不需要 |
| 同文件 `snapuserd -ublk` 的 `-ublk` | 去掉 | legacy A/B 不用 snapuserd；留着会指向 ublk 后端，与 `CONFIG_DM_USER` 缺失的现状不符 |
| `system/build.prop` 的 `ro.virtual_ab.ublk.enabled` / `ro.virtual_ab.userspace.snapshots.enabled` | 删 | 两条属性是 VABC 的开关，legacy A/B 必须让引擎走老路 |
| `system/etc/init/gk3-logdump.rc`、`system/etc/gk3-logdump.sh` | 整份删 | 开机后 20/25/30 秒往 `/metadata` 灌 dmesg/logcat/getprop/ps/SF/window + tombstone，还常驻一个 root service |
| `system/bin/update_engine` 的 3 字节补丁 | **保留** | 与 VABC 无关：`EraseSystemOtherAvbFooter` 在分区元数据初始化路径上，本机没有 `system_other` 也没有它的 AVB 信息，不打就 `kInstallDeviceOpenError (7)` |

调试需要时，`vendor/gaokun-android/device/huawei/gaokun3/debug/` 里有逐字节副本 + `apply_debug_overlay.sh`
（幂等，`TREE=` 可指向任意树），叠回后照常重打；发布镜像不带。

校验链：`rebuild_system_patched.sh` 第 3 步现在会硬拦——build.prop 里还有 `ro.virtual_ab.*`、
snapuserd.rc 里还有 `gk3run`/`gk3clean`、或 `gk3-logdump.rc` 还在，任何一条成立就 `exit 5`。

## 端到端 OTA 实测（2026-11-26，legacy A/B + 自签 payload）

**先说结论：`update_engine` 的写入链路本身完全可用，但 payload 不能只带一部分分区。**

### 第 1 次：3 分区小包（`system` / `my_region` / `my_manifest`，1.07 GiB）

`update_engine_client --payload=file:///… --update --follow` → `kSuccess (0)`，RC=0。回读目标槽（当时在 `_b`，目标 `_a`）：

```
system_a      sector 2048     2221480 blocks  sha 4011db1d…  与源一致
my_manifest_a sector 2223528  1400            sha c9c9803e…  与源一致
my_region_a   sector 2224928  14136           sha c29b97f6…  与源一致
```

但**元数据被按 manifest 重建**了：目标槽只剩这三个分区，另外 10 个 `_a` 分区从表里消失，且三个分区被重新紧凑分配（`my_manifest_a` 从 19,636,224 挪到 2,223,528）。

⇒ 部分分区 payload 会让目标槽**必然起不来**（其余 10 个分区挂不上）。这条决定了：**payload 必须覆盖 13 个动态分区**。

### 第 2 次：13 分区全量（10,059,526,144 B，9.36 GiB）

`kSuccess`，元数据 26 个分区齐全，A 槽被紧凑重排为 2048 → 19,649,560（B 槽 extents 原样未动）。
抽验四块区间（`dd bs=512 skip=<sector> count=<blocks>` 后 `sha256sum`）全部与源一致：

| 分区 | sector | blocks | sha256 |
|---|---|---|---|
| system_a | 2048 | 2,221,480 | `4011db1d…` |
| vendor_a | 4,477,584 | 1,048,576 | `dd574c17…` |
| my_stock_a | 11,766,832 | 7,864,568 | `932bec9e…` |
| my_region_a | 19,632,800 | 14,136 | `c29b97f6…` |

BCAB 被引擎自己改成 `a: pri15 tries6 ok0` / `b: pri14 tries1 ok1`（切槽走的是 boot HAL，不需要 `update_engine_client --switch_slot`）。

### 第 3 次踩的坑：**目标槽起不来，且 gk3boot 三个条目一起"失败"**

A 槽起不来的真因是内容混装（`system` 用了 v50 时期补丁版，其余 11 个分区用了 v52 构建），与 OTA 机制无关。
而 gk3boot 的 A/B 两条 + 直连 A 三条一起十秒自重启，是同一个原因串起来的：BCAB 里 A 优先级仍最高、
`tries` 还没烧完，gk3boot 不管 `gk3.hint=a/b` 都去启 A，失败 → 重启 → 再烧一次 tries。
**排查这类问题时先看 BCAB，不要按条目名分别怀疑。**

### 第 3 次：以「在跑槽的克隆」为准，成功

把 `_b` 的 13 个分区按 extents 原样 dump（`dd if=super bs=512 skip=<sector> count=<blocks>`）→ 13/13 sha 与设备一致
→ 用这一个目录做包（`parts.lock` 记录每份 sha）→ `kSuccess` → 重启。

```
slot_suffix=_a            boot_completed=1        ro.boot.gk3boot.event=none
ro.boot.selinux=permissive   getenforce=Permissive   /dev/block/mapper 里 _a 13 个
A 槽抽验：system 4011db1d… / vendor dd574c17… / my_stock 17a19bda… / my_region 5783ff83…
BCAB 回写：slot_a pri=15 tries=1 ok=1  ← 6 → 1，markSuccessful 生效
```

⇒ **legacy A/B + 自签 payload 的端到端链路成立**：下载 → 校验签名 → 写目标槽 → 重建元数据 → 切槽（BCAB）→ 重启 →
开机完成后 `markBootSuccessful`。legacy A/B 没有 `--merge` 这一步（那是 VABC 的）。

### 第 4 个坑：Windows 上生成的 `payload.bin.properties` 是 CRLF

`kPayloadHashMismatchError (10)`，原因不是哈希算错，而是 properties 每行尾带 `\r`，
`FILE_HASH` 解析出来是 `…Mw0=\r`，跟实际哈希对不上。生成器已改成
`open(props_path, "w", encoding="utf-8", newline="\n")`。设备侧应急可以用 `tr -d "\r"` 洗一遍。

1. **payload 源必须是单一来源。** 从散落的 `v49/`、`v50/`、`v52/`、`current/parts`、`current/zb` 里各挑几个拼一套，
   混装几乎必然起不来（这个错已经犯过多次）。现在固定做法：源 = **设备上已验证能启动的那一槽的原样 dump**
   （`dd if=super bs=512 skip=<sector> count=<blocks>` 逐分区导出）+ `parts.lock` 记录每份 sha，
   生成器只吃这一个目录。
2. **每次 OTA 之后都要重 parse 元数据**（`lp_ab_meta.py parse`），因为引擎会重排目标槽 extents、重写 group、并给 header 打 `virtual_ab` 标志。
   本次 header flags = `1953724787`（bit0 置位）——说明运行镜像里还带着 `ro.virtual_ab.*`，引擎仍按 VABC 分支建元数据。
   清理版镜像上线后要复测一次，确认回落成 legacy 形态。

## 待办

- 用清理后的树重打一次 `system.erofs` 并上机验证（当前设备跑的仍是旧镜像，后门还在）
- `update_engine` 的 3 字节 AVB 补丁在 legacy A/B 下重跑一次分槽安装复核（计划保留）
- 端到端 OTA：payload 写另一槽 → `bootctl SetActiveSlot` → 重启 → 开机完成 markSuccessful → 失败则回滚
- `my_engineering_b` 仍是 OPPO 证书，`otacerts.zip` 只进了 `my_engineering_a`，发布流水线要把两边都换成自签



## 第四次：真实升级内容（发布清理版 system）— 2026-11-26 03:33–03:55

前三次 payload 的内容都是「在跑槽的克隆」，等于自证，不构成升级。这次换成真的新内容：

1. `build/rebuild_system_patched.sh` 在**已清理的构建树**上重打 → `current/parts/release/system.erofs`，
   `185b4991…`（1,137,397,760 B）。镜像内自检：`update_engine` md5 `dc757f0a…`（AVB 补丁在位）、
   `ro.virtual_ab` 0 条、`snapuserd -ublk` 0 处、`gk3-logdump.rc/.sh` 已不存在、`gk3run`/`gk3clean` 两段已不存在。
2. 只换 system，其余 12 个分区照主账本 → 生成候选账本 `current/manifest.release.json`（13/13 自证通过）→
   `make_payload.py --manifest` 出包：10,059,528,316 B，sha256 `bbd9901e…`，manifest sha `a0871a8a…`。
   设备侧先 `sha256sum` 复核 payload 再开 OTA（`kPayloadHashMismatch` 那次 CRLF 事故之后加的保险）。
3. `adb push` 10 GB：**201 s / 47.7 MB/s**（Wi-Fi，比 USB 那条 36 s 慢一个数量级，规划上按 4 分钟算）。
   引擎安装 **81.6 s**，`onPayloadApplicationComplete(kSuccess)` → `UPDATED_NEED_REBOOT`。
4. 重启 → `slot_suffix=_b`、`boot_completed=1`、`event=none`、`selinux=permissive`。这是**发布清理版第一次真正上机**。

在运行的 B 槽上复核（全部为 shell 权限，无需 root）：

- `ro.virtual_ab.ublk.enabled` / `ro.virtual_ab.userspace.snapshots.enabled` 均为空
- `/system/etc/init/gk3-logdump.rc`、`/system/bin/gk3clean`、`/system/bin/gk3run.sh` 都不存在
- `/system/etc/init/snapuserd.rc` 里 `gk3run|gk3clean` 0 处、`snapuserd -ublk` 0 处
- `snapuserd` 进程 0 个（legacy 路径没被 VABC 拉起），`/dev/block/mapper` 里 13 个 `_b`
- `ps` 里 `update_engine` 守护进程在跑（它会负责 `markBootSuccessful`）

**这次挖出来的新事实（重要，会误导「回读比对」）**

- 引擎把目标槽重排成「紧贴 A 槽尾部」：`system_b` 从 `19660800` 挪到 **`19649560`**，其余 B 分区同样前移；
  所以按旧 extents 去 `dd` 回读，读到的是**空档里的旧垃圾**（首字节就是 aarch64 机器码，不是 EROFS 超级块）。
  正确回读方式：先 `lp_ab_meta.py parse` 拿新 sector，再 `dd`。
- `super` 头 4 份元数据副本这次**不一致**：`12288`/`143360` 还是旧布局（`system_b@19660800`），
  `77824`/`208896` 是新布局（`system_b@19649560`，内容 sha 实测 `185b4991…`）。四份 CRC 都合法。
  实测开机能进新槽，说明启动路径选的是新布局那份；但**"四份副本一致"不能再当默认假设**，
  以后每次 OTA 后要四份都 parse 一遍比对（`work/meta_copies2.py` 那套逻辑）。
- 两槽现在故意不同源：B = 发布版（无 root 通道），A = 调试版（`gk3run` 还在）。想回 A 用 gk3boot 的
  `ColorOS 17 - slot A` 条目；BCAB 现在 `b:15/6/0`（引擎置的 tries=6 + ok=0），
  `markSuccessful` 是否已把 `ok` 置 1 **本轮没法确认**——misc 对 shell 不可读，要等下次进 rooted 槽再读 `misc`。

## 待办

- 进 A 槽读一次 BCAB，确认 `markSuccessful` 是否生效（`b:15/1/1`）
- `update_engine` 的 3 字节 AVB 补丁在 legacy A/B 下重跑一次分槽安装复核（计划保留）
- `my_engineering_b` 的自签证书这次已验证（实测 `ce71e4b6…`，与账本一致）；A 槽仍是旧版，等 A 也升级时一并统一
- 原厂「软件更新」UI 复刻 + App 端 `applyPayload` 还没接；当前 OTA 仍是 `update_engine_client` 手动跑
