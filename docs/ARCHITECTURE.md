# 架构与构建总览

## 设备

- 机型：**OPD2513 / gaokun3**（华为 MateBook E Go，SC8280XP，13.2" 320dpi 面板）
- ColorOS 17.0.1（Android 17），`ro.build.date` Wed Nov 4 23:52:11 CST 2026
- 内核 `7.2.9-gaokun3+`，SELinux permissive（移植期）
- 双系统：Windows（ESP + systemd-boot 入口）+ ColorOS（`slot_a`）

## 分区

| 分区 | 起始/大小 | 说明 |
|---|---|---|
| esp | 1 MiB / 300 MiB | systemd-boot + `<machine-id>/android/slot_{a,b}/` |
| boot_a / boot_b | 各 64 MiB | v2 头，kernel + ramdisk + dtb（dtb 必须留在 boot.img） |
| super | 20 GiB | 动态分区，双槽 virtual-ab |
| userdata | ~129 GB | ColorOS 数据 |

单槽 13 个分区（`system`、`system_ext`、`product`、`vendor`、`odm`、`my_product`、`my_stock`、
`my_manifest`、`my_region`、`my_engineering`、`my_heytap`、`my_carrier`、`my_bigball`），
当前单槽 10,059,526,144 B → 双槽 20,119,052,288 B < 21,473,689,088 B。

## 基座目录（构建机 / WSL）

```
/home/cenmin/coloros-build/current/
├── parts/{system.erofs, odm.erofs, vendor.img, my_product.erofs, my_stock.erofs}
├── manifest.json      # 每个分区真实路径 + bytes + sha256 + 不变量
├── release/super.img
└── logs/pack.log
```

`system_ext`/`product`/`my_*` 从未改过，软链/引用 `/home/cenmin/coloros-build/v49/src/`，路径与 sha 由 manifest 记录。
解包树：`/home/cenmin/v50-build/{system,my_product,my_stock,odm,system_ext}`（`fsck.erofs --xattrs` 解出，保留 SELinux 标签）。

工具链：`simg2img`、`mkfs.erofs 1.9.4`、`fsck.erofs`、`dump.erofs`、`zstd`、`debugfs`、`lpmake`（`tools/otatools/bin`）、
`lpunpack`（`/home/cenmin/tools/lpb/binary/lpunpack`，不认 `-i`）。

## 镜像组装

1. `mkfs.erofs -zlz4 -b4096 -C65536 -L <分区名>` 重打 `system`/`odm`。
2. `vendor` 是 ext4（512 MiB），先在镜像里改 rc，再 `e2fsck -fn`。
3. `lpmake -S -F -d 21474836480 -m 65536 -s 3 --virtual-ab -b 4096 -g gaokun3_dynamic_partitions_a:21473689088`
   逐分区 `-p name_slot:none:<bytes>:gaokun3_dynamic_partitions_a`，b 槽用零填充占位。
4. 产物必须是 **sparse**（安装器只认 sparse），展开尺寸正好 20 GiB。

## 启动链与已修的关键点

| 环 | 现状 |
|---|---|
| bootloader → boot.img（含 dtb） | 正常；`boot.img` 必须带 dtb，否则安装器写 0 字节 |
| init 第一阶段挂载 /system | 正常；`/system/etc/firmware` 是 ueventd 第一搜索路径 |
| ath11k（WCN6855）固件 | 固件已进 `/system/etc/firmware/ath11k/WCN6855/hw2.1/`，原 `write …ath11k_pci/bind` 改为 `exec_background`，不再堵 init 62 s |
| SurfaceFlinger / launcher | `debug.hwui.renderer=skiavk` + turnip `queueCount` 2，修掉 `drawRenderNode … no surface` |
| 显示密度 | 真实 320；ColorOS 中途会把 `persist.sys.display.density` 写成 480，rc 里 `on property:…=480 → 320` 立刻掰回 |
| 充电 | 仍缺库：`odm/lib64` 需要 `libjsoncpp.so`（已放）、`android.hardware.sensors-V3-ndk.so`、`libhidltransport.so` |

## 补丁清单（语义，不含逐字节细节）

| 补丁 | 落点 | 作用 |
|---|---|---|
| vendor turnip `queueCount` 1→2 | `/vendor/lib64/hw/vulkan.freedreno.so` 两处单字节 | 修 launcher RenderThread 无 surface 崩溃（黑屏） |
| `debug.hwui.renderer=skiavk` | `/vendor/build.prop` | 同上，走 Vulkan 后端 |
| vendor 几何修复 | vendor ext4 镜像 | 先 `resize2fs -f IMG 131072` 再 `truncate -s 512MiB`，避免 `bad geometry` |
| ath11k 固件 + rc 非阻塞 | system / vendor rc | 开机不再卡 62 s |
| 密度属性触发 | `/system/etc/init/gaokun3-v43.rc` | 480 → 320，解决控件混排 |
| 充电库补齐 | `odm/lib64` | 让 `oplus_charger_hal_service` 能链接 |
| SystemUI 充电补丁 | `/system/etc/gk3-charge/SystemUI.apk` + zygote 命名空间 bind | `OplusAddBatteryStatus` 从附加广播取真实插拔状态（HAL 修好后可能可以撤） |
| 首启 provisioning | `gaokun3-postboot.sh` | `device_provisioned=1`、`user_setup_complete=1` |

## 发版形态

- **开发期**：只出 sparse `super.img` + sha，安装器“卸载再安装”刷入（会清数据）。
- **正式版**：`super.img.zst` + `boot.img` + sha256 清单 + 一个全量 OTA 包（update_engine 本地安装）。
