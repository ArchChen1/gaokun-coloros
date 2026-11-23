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

## 最新出包（current）

见 `manifest.json` 与 `latest/super.img.sha256.txt`；当前值：
sha256 `a3d0d0f3508d21f98e4c679b84132987798c08d22fbc6e633559b8025dae6b0b`，9,833,219,624 B。
