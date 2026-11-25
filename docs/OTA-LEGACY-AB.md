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

