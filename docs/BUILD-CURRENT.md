# 当前基座目录（唯一可信来源）

> 立此文档的直接原因：v53 打包时把 vendor 从 `v50`（未打黑屏补丁）而不是 `v52`（已验证上机）派生，
> 结果整套退回「亮黑屏」。补丁链此前只存在于叙述里，磁盘上没有任何东西会挡住这类错误。
> 从这版起，**正确基座是目录，不是记忆**。

## 位置

| 用途 | 路径 |
|---|---|
| 唯一基座（分区产物 + 断言清单） | `/home/cenmin/coloros-build/current/`（WSL） |
| 分区产物 | `current/parts/{system.erofs,odm.erofs,vendor.img,my_product.erofs,my_stock.erofs}` |
| 出包结果 | `current/release/super.img`、`current/logs/pack.log` |
| 构建账本 | `current/manifest.json`（每个分区的真实路径 + 字节数 + sha256 + 不变量） |
| 对外发布 | `D:\gaokun-coloros-release\latest\`（HTTP `http://192.168.1.152:8001/latest/`） |

`system_ext/product/my_*` 这些从未改动过的分区不复制，`manifest.json` 记录它们在
`/home/cenmin/coloros-build/v49/src/` 的真实路径与 sha256。

## 四支脚本（都在 `coloros-port/scripts/`）

1. `current_verify.sh` —— **断言的唯一出口**。13+ 条硬断言，任一 FAIL 就打印 `VERIFY_FAILED` 并退出非零。
2. `current_build.sh` —— 固化基座：vendor 从 `v52/vendor_a_v52.img` 派生（重打 rc 补丁）、软链其余分区、
   跑 `current_verify.sh`、从断言过的树重打 `system.erofs`/`odm.erofs`、写 `manifest.json`。
   要强制重打 vendor：`FORCE_VENDOR=1`。
3. `current_pack.sh` —— 读 `manifest.json` 出 super（脚本内先复跑 verify），算 sha，拷到 `latest/`。
4. `current_cleanup.sh` —— 清盘，全部路径硬编码 + 前缀白名单守卫，禁止变量拼路径删除。

## 断言清单（改这些就等于改“什么叫正确”）

system 树：ath11k 四件固件齐全 / rc 有密度属性触发 / postboot 不 kill SystemUI / postboot 调充电挂载 /
充电补丁二进制在 / postboot 有执行位
odm 树：`lib64/libjsoncpp.so` 存在
vendor 镜像：`vulkan.freedreno.so` = `7619b128…1d90`（黑屏修复位）/ `debug.hwui.renderer=skiavk` /
rc 无同步 `write …ath11k_pci/bind`、有非阻塞兜底 / `v29_usb_capture.sh` 标签 = `gaokun3_wlanap_exec`
其余：my_product、my_stock、v49 src 全部存在

## 规矩

- 出包只走 `current_pack.sh`，它必跑 verify；不允许手写分区列表，不允许临时拼基座。
- 新补丁先落到 `current/parts`（或先改树再 `current_build.sh`），验证过后才算“当前正确”。
- vendor 只许从 `v52/vendor_a_v52.img` 派生，不许从 v50 或 donor 原始镜像重新推导。
- 每次出包 sha256 必须同时出现在 `manifest.json`、`latest/super.img.sha256.txt`、对话汇报里，三处一致。
- 长时间任务（>5 分钟，尤其整包重建）先报批准。

## 正式发版 vs 开发

- **开发期**：只出 `super.img`（sparse，展开正好 20 GiB）+ sha，供安装器卸载重装使用。
- **正式发版**（未来）：`super.img.zst` + `boot.img` + sha256 清单 + 一个全量 OTA 包（update_engine 可本地安装）。
  开发期不做 zst 与 OTA 整包。

## 事故台账

| 版本 | 问题 | 根因 |
|---|---|---|
| v53 | 亮黑屏，与 v48–v50 同症状 | vendor 误用 `v50`，丢失 turnip `queueCount` 两字节补丁与 `skiavk` |

## 2026-11-26：设备实证基线（A/B 两槽同源）

这一轮 OTA 试验把「设备上真能启动的那套」dump 下来做了账本，13 个分区的 sha 如下
（`tools/ota/parts_manifest.py write --parts <dump目录>` 生成的 `work/manifest_fromB.json`）：

| 分区 | 字节 | sha256（前 16） | 账本里原来的值 |
|---|---|---|---|
| system | 1,137,397,760 | `4011db1d57993077` | `f8770b1c…` ← **旧账本记的是未打补丁的基座** |
| system_ext | 986,378,240 | `6f2e5102c5b0d3f3` | 同 |
| product | 167,698,432 | `6750e8e32c064b8d` | 同 |
| vendor | 536,870,912 | `dd574c1756496e2f` | `5a5853c5…` ← **旧账本记的是 C2 补丁前** |
| odm | 2,131,279,872 | `5f014b79a4e68ee9` | 同 |
| my_product | 1,063,944,192 | `cd445c2673253734` | 同（v52 层） |
| my_stock | 4,026,658,816 | `17a19bda72fe5d3a` | 同（v52 层） |
| my_manifest | 716,800 | `eb2c3ebdf42a36ab` | 同 |
| my_region | 7,237,632 | `5783ff83d3640b64` | 同 |
| my_engineering | 335,872 | `ce71e4b632eac3f6` | `f38ccd36…` ← **证书版产物从未落盘** |
| my_heytap | 335,872 | `083e1ebbbdb9866b` | 同 |
| my_carrier | 335,872 | `61171f0c977eafc0` | 同 |
| my_bigball | 335,872 | `d5fc02100b528046` | 同 |

结论：旧 `current/manifest.json`（2026-11-24 06:18）在 system / vendor / my_engineering 三处已经**过期**。
它记的 sha 与设备上真跑的那份不一致，而这个账本从来没有人核对过 —— 这就是「补丁老是丢」的结构性原因。

## 硬约束（2026-11-26 起生效）

1. **账本自证。** `build/current_pack.sh` 与 `tools/ota/make_payload.py --manifest` 都会逐分区核对
   `bytes` + `sha256`，任一不符直接 `PART_SHA_MISMATCH` / 退出。出包、出 payload、发布，
   都只认账本，不再接受「目录里正好有这几个文件」。
2. **补丁产物必须落盘在基座目录。** `current/parts/`（或 `builds/<版本>/`）之外不许有产物；
   `work/`、`/mnt/e/.../work/` 一律视为临时目录，不许当来源。
   （本轮 system 的补丁版只在 `work/system_patched.erofs`，my_engineering 的证书版干脆没落盘 —— 两处都要补齐。）
3. **`vNN` 不是版本号。** v52 只有 `my_product` / `my_stock` / `vendor` 三个分区，它是**补丁层**，不是「v52 全套」。
   说「用 v52」既对（vendor 要从这一层派生）又错（其余分区根本不在那儿）。版本只有 `manifest.json` 一个说法。
4. **改分区 = 改账本。** 任何对分区的改动，必须同时更新 `manifest.json`（新 sha）并在
   `docs/BUILD-CURRENT.md` 事故台账里记一行「改了什么、为什么」。

## 待补齐的产物（当前缺口）

- `my_engineering` 的证书版（`ce71e4b6…`）：设备上有，产物没有。需要一条 `build/patches/*.sh`
  从 `v49/src/my_engineering_a.img` 派生并校验，否则发布包会把 OPPO 原证书带出去。
- vendor 的 C2 补丁（`dd574c17…`）：只有产物，没有可复跑的脚本（`v52/ca5ba84b…` → C2 这一段）。
- system 的补丁版（`4011db1d…`）：由 `build/rebuild_system_patched.sh` 从 v50 树重打，产物应固定落到
  `current/parts/system.erofs`，而不是 `work/`。


## 最新出包（current）

见 `manifest.json` 与 `latest/super.img.sha256.txt`；当前值（2026-11-24 那次的 `super.img`，已被上面的基线取代，仅供追溯）：
sha256 `a3d0d0f3508d21f98e4c679b84132987798c08d22fbc6e633559b8025dae6b0b`，9,833,219,624 B。
