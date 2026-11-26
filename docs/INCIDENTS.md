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
- **2026-11-26 进展：缺库已修，但真因更深一层。**
  两个 so 经 `build/patches/p_odm_charger_libs.sh` 补进 `odm/lib64` 并随增量包刷入 B 槽，
  手动运行 `/odm/bin/hw/vendor.oplus.hardware.charger-V12-service` 不再报缺库
  （只剩 shell 身份下的 `registerChargerService failed: status=-3`，属预期）。
  但 init 拉起仍 `restarting`：**`/sys/class/oplus_chg` 不存在**。
  该 HAL 依赖 OPPO 自家充电驱动的 sysfs 接口，本机内核提供的是华为 EC 的
  `gaokun-ec-battery` / `gaokun-ec-adapter`，HAL 找不到节点就 abort。
  标准电池路径是通的（`dumpsys battery` 的 level/voltage/technology 均来自 EC）。
  两条路：A. 内核仿造 `oplus_chg` 接口（工作量大、收益不确定）；
  B. 绕开 oplus HAL，走标准 health HAL + SystemUI 适配（即 gk3-charge 补丁的方向，推荐）。
  尚未拍板；且验证充电行为必须物理插上充电器。

### 5.1 采用 B 方案：改框架合成 notifyCode（不动 SystemUI，绕开签名）

用户拍板走 B。进一步排查后，落点比「改 SystemUI」更靠前、也更干净：

**为什么不改 SystemUI**：`/system_ext/priv-app/SystemUI/SystemUI.apk`（原版 sha `8b118f6f…`）
是 v3 平台签名（`SignType: platform_sha256`，指纹 `E4980240…`），OPPO release-keys，
仓库和 WSL 里都没有对应私钥。重签会丢 signature 级权限，不可行。
`/home/cenmin/archive/gk3-charge-20261126/SystemUI.apk` 是当年**已打补丁的候选**，不是在跑的原版。

**原版 SystemUI 的精确语义**（取自 jadx `--fallback` 字节码，普通反编译会把这段控制流还原错）：

```
isFull          = (status == 5) && !(notifyCode & 1024 || notifyCode & 2048)
batteryCharging = plugged != 0 && !isFull && !(notifyCode & 2 || notifyCode & 32)
```

即 bit2 / bit32 是「不充电」标志位。`notifyCode = -1` 把所有位都置上，于是**插电也判定为不充电**。
`notifyCode = 0` 才是「无故障」。

**数据来源链**：`OplusBatteryService.getBroadcastDataFromHal()` →
`mChargerInfoUpdateSupported == -1`（HAL 不可用）→ `getDataFromHalByOldInterface()` →
`mBatteryNotifyCode = feature.getPsyBatteryNotify()`，而后者 `ensureConnect()` 失败即 `return -1`。
`mPlugType` / `mBatteryStatus` 则来自标准 BatteryService（`processAdditionalValuesLocked`），**是准确的**。

**补丁**（`build/patches/p_charger_notifycode.py`，改 `oplus-services.jar` 的 smali）：
HAL 返回 -1 时用标准状态合成等价标志，HAL 可用时原样保留厂商值：

| 实际状态 | 合成 notifyCode | SystemUI 结果 |
| --- | --- | --- |
| 未插电 | 0 | 不充电 |
| 插电 + status 2（充电中） | 0 | 充电，显示闪电 |
| 插电 + status 5（充满） | 0 | isFull，显示满电 |
| 插电 + 其他 status（暂停充电） | 2 | 不充电 |

jar 不走 APK 签名校验，因此不需要任何密钥。方法 `.locals 7 → 9`，用全新的 v7/v8，不碰原有寄存器。

**已验证**：重建后 `classes.dex` 以 **STORED** 方式换回原 jar（普通 `zip` 会 deflate，
ART 需要不压缩才能 mmap），`zipalign -c 4` 通过；jar 内**只有 classes.dex 变化**，其余条目逐字节保留；
jadx fallback 复核字节码，分支与设计完全一致。产物 `work/charge/oplus-services-aligned.jar`
（30,758,288 B，sha 见构建日志）。

**待做**：把 jar 放进 system 树、清掉 `oat/arm64/oplus-services.{odex,vdex}` 旧产物、
重打 system.erofs → 出增量包（只有 system 变）→ 刷写验证。
**验证必须插上充电器**（当前 `gaokun-ec-adapter online=0`，设备在用电池）。

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
