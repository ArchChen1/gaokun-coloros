# 事故台账

每条记录“症状 → 根因 → 现在的防线”。新坑先写这里，再写进 `build/current_verify.sh` 的断言。

## 1. 亮黑屏（v48–v50），v51 修复，v53 回归

- **症状**：SurfaceFlinger 在合成，屏幕亮但全黑；`logcat` 里 launcher `RenderThread` 崩：
  `Abort message: 'drawRenderNode called on a context with no surface!'`（`libhwui.so SkiaOpenGLPipeline::getFrame()`），
  SF 持续 `trackPendingFrame: Invalid present fence`。
- **根因**：turnip（`vulkan.freedreno.so`）此版本 `queueCount` 为 1，配合 `skiagl` 后端拿不到可用 surface。
- **修复（v51）**：驱动两处单字节 `1→2`，`debug.hwui.renderer` 由 `skiagl` 改 `skiavk`。用户确认进桌面。
- **v53 回归**：新写的打包脚本把 vendor 从 `v50`（未打补丁）派生，症状与 v48–v50 完全一致。
- **现在的防线**：`current_verify.sh` 断言驱动 sha `7619b128…1d90` + `renderer=skiavk`；
  `current_build.sh` 写死只从 `v52/vendor_a_v52.img` 派生。

## 2. vendor 几何损坏

- **症状**：`EXT4-fs (dm-3): bad geometry: block count 320000 exceeds size of device (131072 blocks)`，
  `Failed to mount /vendor`，`init: failed to mount required partitions early`。
- **根因**：先 `truncate` 再 `resize2fs`，缩容失败但超级块仍记 320000 块。
- **修复**：在 1.31 GiB 原文件上先 `resize2fs -f IMG 131072`，再 `truncate -s 536870912`，`e2fsck -fn` 干净。

## 3. erofs 丢 xattr 导致 SELinux 标签消失

- **症状**：`my_product`/`my_stock` 内容在但服务起不来。
- **根因**：`fsck.erofs --extract` 默认不导出扩展属性。
- **修复**：一律加 `--xattrs`；`mkfs.erofs` 打包时保留 xattr。

## 4. 控制中心“有的控件大有的正常”、侧边栏整体偏大

- **根因**：两套密度源。init 在 `post-fs-data` 设 320，**system_server 启动期间把 `persist.sys.display.density` 改写成 480**
  （donor 预设的“厂商密度”），SystemUI 与 SmartSideBar 在 101 s 启动时读到 480 并按它算尺寸；
  postboot 106 s 才改回 320 并重启 SystemUI → 106 s 前建的控件按 480、之后按 320。
- **真实显示配置**：`wm density` Physical 320、`display_density_forced` null，480 纯属 prop 谎言。
- **修复**：`gaokun3-v43.rc` 加 `on property:persist.sys.display.density=480 → setprop … 320`（事件驱动，早于 SystemUI 启动），
  并去掉 postboot 里的 `kill SystemUI`（不再开机白闪）。
- **验证**：真机 `wm density` 320、`mIsDensityForced=false`、无任何矫正脚本在跑，控制中心截图一致。

## 5. 充电图标不动 / 充电 HAL 每秒崩溃

- **症状**：`dumpsys battery` 长期 `PlugType: 0`、`ChargerTechnology: -1`；`service list` 无 `ICharger`；
  `init` 每秒一条 `process … 'oplus_charger_hal_service' exited`。
- **根因链**（逐步暴露，都是 vendor 命名空间看不到 system 库）：
  1. `libjsoncpp.so` not found → 放 `odm/lib64` 后暴露下一个
  2. `android.hardware.sensors-V3-ndk.so` not found（`libsensorndkbridge.so` 需要）
  3. `libhidltransport.so` not found
  三个补齐后二进制可完整链接（shell 身份注册返回 `status=-3` 属正常，init 以 root 起不受限）。
- **辅助手段**：`build/charger_hal_deps.py`（静态依赖闭包）、`tools/gk3_hal_probe.sh`（设备端迭代试探）。
- **遗留**：修好 HAL 后需验证“SystemUI 充电补丁是否可撤”。

## 6. 开机 12 s 卡到 70 多秒

- **根因**：`init.gaokun3.rc:141` 的 `write /sys/bus/pci/drivers/ath11k_pci/bind 0006:01:00.0` 是**同步**命令。
  内核 1.8 s 就 probe WCN6855，但 `/vendor` 未挂载、`firmware_class.path=/vendor/firmware/` 不存在
  → `amss.bin failed with error -2`、`failed to power up mhi: -110`；该 `write` 阻塞 init 流水线 **62 秒**，
  超时后 `/vendor` 挂好、固件加载成功，boot 才继续。
- **证据**：`init: Command 'write …ath11k_pci/bind …' took 62235ms and succeeded`。
- **修复**：固件放到 `/system/etc/firmware/ath11k/WCN6855/hw2.1/`（ueventd 第一搜索路径），
  rc 改成 `exec_background` 兜底重试。
- **效果**：`boot_progress_start` 78.7 s → **16.8 s**，`enable_screen` 104.8 s → **46.7 s**。

## 7. 其它已确认但未修

| 现象 | 说明 |
|---|---|
| `minidumpreader` 每次开机 SIGSEGV | `readRestartInfo()+404` 空指针，无害 |
| `init.nvram.rc` 等 `nonmodemst1` 超时 5 s | 未搬 modem NVRAM 分区 |
| `regulatory.db` 缺失 | WiFi 法规库没有 |
| 大量 avc denied | permissive 下不阻断，但拖慢审计 |
| `init second_stage` SIGABRT tombstone（历史 3 次） | 未定位到具体 service |
| 安装器清数据后 root 消失 | ReSukiSU 需重装（`su`、`/data/adb` 都在 userdata） |

## 8. 流程性事故（v53 的教训）

- **症状**：补丁链只活在对话里，磁盘上没有元数据。
- **后果**：新脚本从错误基座派生，自检全绿却打出黑屏包。
- **防线**：`current/` 基座目录 + `manifest.json` + `current_verify.sh` 断言 + `current_pack.sh` 出包前复检。
