# HyperOS 参考实现 vs ColorOS v36/v37 静态差集审计

日期：2026-11-21

## 1. 审计范围与方法

参考实现：

- `E:\gaokun-coloros\analysis\matebookego_hyperos`
- 主要依据：`scripts/build.py`、`scripts/overlay.py`、`scripts/configure_display.py`、`scripts/patch_xiaomi_va_os4.py`、`assets/`、`docs/`、`CHANGES.md`

当前 ColorOS 审计树：

- system：`/home/cenmin/v25-system/tree/system`
- system_ext：`/home/cenmin/audit-v36/system_ext`
- product：`/home/cenmin/audit-v36/product`
- vendor：`/home/cenmin/audit-v36/vendor`
- odm：`/home/cenmin/audit-v36/odm`
- my_product：`/home/cenmin/audit-v36/my_product`

重要限制：

- HyperOS 仓库没有 `input/`、`artifact/` 或最终 `super.raw.img.zst`，因此不能对 HyperOS 最终分区做逐字节 diff。
- 本报告比较的是 HyperOS 的**已记录构建变更集**与 ColorOS v36 实际分区内容。
- HyperOS 是“小米 Pad 9 HyperOS + crDroid/gaokun vendor”；ColorOS 是“ColorOS + gaokun3 vendor/ODM”。framework/service 与包名不能直接照搬，只能按等价类映射。
- `checkvintf` 主机工具只支持旧版 libvintf，无法解析当前 manifest.version 9.0；VINTF 结论来自 XML/文件/二进制静态检查，不是该工具的运行结果。

## 2. 当前产物指纹

### v36 诊断基线

```text
super.img.zst  sha256 7cd7368693ec851420f1e7951c97c773bfc1c0091b9a928b9e5ad642c04c9533
boot.img       sha256 ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
system-v25     sha256 d3a84a7cdf5c5052e872be3d39cf76251ffa8997bc9a4dc8eec0f808cf49aa2b
vendor_v36     sha256 1799a05f74648c879cf25fdb89b3deda4cd0031640463c1b6f47414699b67e66
```

v36 `metadata-v36run.img` 中只有：

- `gk3-v31-marker`
- `gk3-init-write-test`
- `gk3-boot-write-test`
- `gk3-v32r4-marker`

没有 `gk3-boot-completed-marker`，即没有到达 `sys.boot_completed=1`。

### v37 最小 WFD 静态候选

```text
release-coloros-v37/boot.img       sha256 ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
release-coloros-v37/super.img.zst  sha256 891064364b440f4c358ccd5759ee169cdfdda941791318b2b6a875d6eaeecf5f
super-coloros-v37.simg             sha256 682f89339b02b6b08a60107f48072c20a2dec48386bb10fdad83cff0a1ae09e1
system-v37.erofs                   sha256 5fb00dd5813985670dd7e96b3d733d4d4dc88374e0176c633e43ec458eed65cb
vendor_a_v37.img                   sha256 f953d9e8d6cd0523a24b244cb0dc5f3dccc09f44942e17612f4d9549a3df32a4
```

v37 只做了两件事：

1. `system/build.prop` 的 `persist.debug.wfd.enable=1` 改为 `0`。
2. vendor 删除 `/etc/permissions/android.hardware.wifi.direct.xml`，并在 `init.gaokun3.rc` 的 `on post-fs-data` 加入 `setprop persist.debug.wfd.enable 0`。

未修改 `services.jar`、bootanimation、OTA 门控、现有 `gk3_capture32` 服务。

## 3. 总差集矩阵

状态说明：

- `DONE`：已有等价实现。
- `PARTIAL`：有部分实现，但仍有明确缺口。
- `MISSING`：当前 v36 没有实现。
- `N/A`：参考项不适用于 ColorOS 的包名/架构。
- `BLOCKED`：需要新的定位或方案，不能套 HyperOS 偏移/文件。

| 子系统 | HyperOS 参考实现 | ColorOS v36 | v37 | 结论 |
|---|---|---|---|---|
| WFD 属性 | build.prop=0，并在 init 中 setprop=0 | `persist.debug.wfd.enable=1` | 改为 0，并加 init setprop | v37 已补齐 |
| Wi-Fi Direct 特性 | 不靠该 XML 让 WFD 注册 | `android.hardware.wifi.direct.xml` 存在 | 已删除 | v37 已补齐 |
| 图形库 | 替换 ANGLE 三件套 | 已替换 9 个 crDroid 图形库，`libEGL.so` 无 `kgsl-3d0` | 未变 | DONE |
| libutils VA guard | system/product/gsid 按 56 位地址上界打补丁 | 当前文件没有 HyperOS 识别的 `b2409be8/b240bbe9` 模式 | 未变 | BLOCKED |
| APEX libutils | tethering/wifi/media/media.swcodec 内 libutils 独立 patch + bind | 四个 APEX 的 libutils 均无 HyperOS 模式；无 `gaokun-apex` | 未变 | BLOCKED |
| USB services.jar | UsbService 的 `/sys/class/android_usb` → `/sys/class/udc` | classes3 中仍为 android_usb；v33 直接注入已失败 | 未变 | BLOCKED/冻结 |
| light-service | 用 color 低字节替代 RGB Rec.601 加权 | 仍是旧算法；当前二进制哈希 `3f1690d3...` | 未变 | MISSING，但有新偏移候选 |
| 属性：密度 | 240 基准，显示覆盖层/用户密度另设 | vendor=240，但 my_product=420；存在覆盖冲突 | 未变 | PARTIAL/需运行时确认 |
| 属性：zygote/ABI | `ro.zygote=zygote64_32` | vendor=zygote64_32，odm=zygote64；存在覆盖冲突 | 未变 | PARTIAL/需运行时确认 |
| SF idle/touch/frame-rate | init post-fs-data 设置 1000000/1000000/false | 未发现 | 未变 | MISSING |
| 背景模糊 | build.prop + init 关闭 | 未发现 | 未变 | MISSING |
| GPU min_freq | boot_completed 后写 690000000 | 未发现 gaokun3 的该动作 | 未变 | MISSING |
| displayconfig/RRO | 1600×2560、240 DPI、0.04–1 亮度、120Hz | product 无 `Gaokun3FrameworkOverlay.apk`、无 displayconfig | 未变 | MISSING |
| 缺失特性声明 | 明确 unavailable: ALS/指南针/GPS/电话/NFC | 指南针已删；但 ODM 仍有 light/context_hub/head_tracker/telephony.ims | 未变 | PARTIAL |
| ContextHub | 不声明、不启动 | VINTF/init 已删，但 ODM feature XML 仍在 | 未变 | PARTIAL |
| FindDevice/Thermal | 禁用小米包组件 | ColorOS 没有这些小米包 | 未变 | N/A，需映射 OPlus 等价组件 |
| OTA | 删除 Xiaomi Updater/miupdater | 无 Updater/miupdater；但仍有 ColorOS `OTA`/`cotad` | 未变 | PARTIAL，需确认是否跨机型入口 |
| SELinux audioserver | 加 ashmem + prop 读取规则 | 未发现 audioserver ashmem 规则 | 未变 | MISSING |
| SELinux untrusted_app | 加基础域 ashmem/qemu/proc 规则 | 未发现基础域规则 | 未变 | MISSING |
| ODM SELinux 合并 | 重编译 precompiled policy | vendor precompiled 与 policy-src 哈希一致 | 未变 | DONE（合并本身），但平台规则仍缺 |
| 音频 VINTF | crDroid vendor 路径 | binaural audio policy include 已禁用；provider VINTF 仍保留 | 未变 | PARTIAL |
| USB host | 声明 USB host | `android.hardware.usb.host.xml` 已存在 | 未变 | DONE |
| media.settings.xml | HyperOS 删除 | ColorOS vendor 实际存在 `media_profiles_vendor.xml` | 未变 | N/A |
| graphicsengine.rc | 给小米服务加 disabled | ColorOS 没有该 rc | 未变 | N/A |
| bootlog | 持久日志服务 | 无 bootlog；v36 用 init 标记 | 未变 | 不作为阻塞项 |

## 4. 关键发现

### 4.1 WFD：v37 的方向正确

ColorOS `DisplayManagerService.smali` 已确认：

- 资源布尔为 false；
- `persist.debug.wfd.enable != 1`；
- 非 MTK WFD；
- 三者成立时不注册 `WifiDisplayAdapter`。

v36 同时具备 `persist.debug.wfd.enable=1` 和 `android.hardware.wifi.direct.xml`，会进入 P2P/WFD 注册路径。v37 已同时关闭属性并删除 XML，这是当前最干净的静态对照。

### 4.2 属性覆盖冲突

当前实际属性文件存在两组高风险覆盖：

```text
vendor/build.prop:      ro.sf.lcd_density=240
my_product/build.prop:  ro.sf.lcd_density=420

vendor/build.prop:      ro.zygote=zygote64_32
odm/build.prop:         ro.zygote=zygote64
```

如果 `my_product`/`odm` 的属性加载顺序晚于 vendor，实际值可能是 420 和 64 位-only。HyperOS 的 240/zygote64_32 不能证明 ColorOS 当前也取到这些值。下一版应在静态构建时统一这些重复值，或在能取到 ADB 时用 `getprop ro.sf.lcd_density`、`getprop ro.zygote` 确认。

### 4.3 libutils/APEX：不能套 HyperOS 偏移

当前检查结果：

- `/system/lib64/libutils.so`：无 `b2409be8`、`b240bbe9`、`b240dfe0`
- `/system/lib/libutils.so`：同样无
- `/product/lib{,64}/libutils.so`：同样无
- `/system/bin/gsid`：同样无
- `com.android.tethering/wifi/media/media.swcodec` 的 APEX libutils：同样无

因此 HyperOS 的 `patch_xiaomi_va_os4.py` 不能直接应用。需要按 ColorOS 的实际指令模式重新定位，或从源码重建对应库；目前应标记为 BLOCKED，而不是“未做所以补一个偏移”。

### 4.4 音频/SELinux：明确缺口

当前 `plat_sepolicy.cil` 没有：

```text
(allow audioserver ashmem_libcutils_device ...)
(allow audioserver ashmem_device ...)
(allow audioserver bootanim_system_prop ...)
(allow audioserver vendor_default_prop ...)
(allow untrusted_app ashmem_libcutils_device ...)
(allow untrusted_app qemu_hw_prop ...)
(allow untrusted_app proc_version ...)
```

HyperOS 文档明确记录：缺少 audioserver ashmem 会导致 AudioTrack 控制块分配失败（`-12`），进而导致无声音/部分播放器黑屏；缺少 `untrusted_app` 基础域规则会导致 targetSdk 较高应用（如 Edge）启动即退出。该缺口与 WFD 无关，应在后续版本补入并按当前 ColorOS 策略重新编译。

当前 `precompiled_sepolicy` 与 `coloros-build/policy-src/gaokun_vendor/precompiled_sepolicy` 哈希一致，说明 ODM/vendor 策略合并链本身是通的；缺的是平台规则内容，不是合并产物丢失。

### 4.5 缺失特性：当前仍有假声明

当前 ODM 中仍存在：

```text
/home/cenmin/audit-v36/odm/etc/permissions/android.hardware.sensor.light.xml
/home/cenmin/audit-v36/odm/etc/permissions/android.hardware.context_hub.xml
/home/cenmin/audit-v36/odm/etc/permissions/android.hardware.sensor.dynamic.head_tracker.xml
/home/cenmin/audit-v36/odm/etc/permissions/android.hardware.telephony.ims.xml
```

其中：

- `sensor.light`：gaokun3 没有 ALS，但 feature 仍声明存在。
- `context_hub`：v26 只删了 ContextHub VINTF/init，feature XML 仍在。
- `head_tracker`：没有对应硬件/服务。
- `telephony.ims`：本机无 modem，但 feature 仍声明。

HyperOS 的做法是用 `gaokun3-unavailable-features.xml` 统一声明 unavailable。ColorOS 当前没有该文件，也没有等价的 feature 清理。这个差集应优先于“删除 Updater”这类非启动项。

### 4.6 音频 VINTF：已做一部分

`/home/cenmin/audit-v36/odm/etc/audio/audio_policy_configuration.xml` 中 binaural 的 `<module name="binaural_record">` 已被替换为注释，说明 v23/v24 的音频策略修复仍在。

但仍存在：

```text
/home/cenmin/audit-v36/odm/etc/vintf/manifest/binaural_record.xml
/home/cenmin/audit-v36/odm/etc/vintf/manifest/manifest_oplus_virtualdevice_audio_aidl.xml
```

对应 ODM 中有 `lib64/hw/audio.binaural_record.default.so`、`libvirtualaudio.so` 等库，但没有找到对应 init service。它们未必像 `audio.core IModule` 那样阻塞 AudioPolicyService，但在 VINTF/服务层面仍不是干净状态。建议单独验证，不要和 WFD 改动混在一起。

### 4.7 light-service：有可重新定位的候选

当前二进制：

```text
vendor/bin/hw/android.hardware.light-service.gaokun3
sha256 3f1690d396e9269f699f37781074e75f7db000b71abc3db10554fa02b56fca13
```

旧算法指令：

```text
file offset 0x393d4: 53087d08  lsr w8, w8, #8
```

上下文是 RGB Rec.601 加权计算，和 HyperOS 记录的旧逻辑一致。HyperOS 的 `0x39400048` 候选（`ldrb w8, [x2]`）不能套 `0x37094` 偏移，但可以在当前 `0x393d4` 重新验证。该修复仍未落地，不能标记为“已完成”。

### 4.8 USB：逻辑缺口仍在，但不要重试 v33 注入

当前 `services.jar` 的 `classes3.dex` 中仍有：

```text
/sys/class/android_usb
```

`UsbService.smali` 的检查位于 `classes3`，而 `UsbDeviceManager` 里已有 `/sys/class/udc/`。HyperOS 的逻辑是只把 `UsbService` 的那个检查改成 `/sys/class/udc`。当前 ColorOS 需要同样的逻辑，但 v33 的直接 jar 注入已确认失败，不能重试同路线。后续应改用可验证的 framework 源码构建、离线 dex 替换并删除旧 odex/vdex/art 的完整方案，或先通过运行时 bind/验证确认问题。

### 4.9 OTA：不是简单“删除 Updater”

当前 ColorOS：

- 没有 `product/app/Updater`
- 没有 `system_ext/etc/init/miupdater.rc`
- 仍有 `system_ext/app/OTA`、`system_ext/bin/cotad`、`system_ext/etc/init/cotad.rc`

HyperOS 删除的是 Xiaomi Updater/miupdater，不能直接映射成“ColorOS 没有做 OTA 清理”。ColorOS 的跨机型入口更可能是 `OTA` + `cotad`。是否删除/禁用需要先确认其是否绑定 OPlus 云和机型校验，避免误删 AOSP `update_engine/update_verifier`。

### 4.10 显示/RRO/120Hz

当前 product：

- 没有 `Gaokun3FrameworkOverlay.apk`
- 没有 `product/etc/displayconfig`
- 没有 `product/overlay/config/config.xml`

当前属性：

- `persist.graphics.egl=angle`、`ro.hardware.gralloc=minigbm`、`ro.hardware.vulkan=freedreno` 已存在
- SF idle/touch/frame-rate、背景模糊、GPU min_freq 均未发现

HyperOS 的 120Hz 修复不仅是 build.prop，还包括 `configure_display.py` 的 secure/system settings、displayconfig、RRO 和 SF 属性。ColorOS 当前这一整组仍未做。

## 5. 建议的后续版本顺序

### v38：先做“不改变启动路径”的静态清理

优先级最高，且与 v37 不冲突：

1. 补 SELinux audioserver / untrusted_app 基础域规则。
2. 删除或 unavailable 化 ODM 的 `sensor.light`、`context_hub`、`head_tracker`、`telephony.ims` feature。
3. 统一 `ro.sf.lcd_density` 与 `ro.zygote` 的重复定义。
4. 再评估 binaural/virtual provider VINTF 是否需要清理。
5. 不改 `services.jar`，不改 OTA 主流程。

### v39：显示/性能

1. light-service 在 `0x393d4` 重新验证补丁。
2. 加入 SF idle/touch/frame-rate 属性。
3. 加入 GPU min_freq 690MHz 的 boot_completed 动作。
4. 加 displayconfig/RRO，先只做 1600×2560/240 DPI/120Hz/亮度映射。
5. 再关闭背景模糊。

### v40：USB/framework 与 APEX

1. 只做一次受控的 services.jar USB 方案验证，不再走 v33 直接注入。
2. 按 ColorOS 实际指令模式重新定位 libutils/APEX VA guard。
3. 若无法定位，考虑源码重建而不是盲补。

### OTA/Updater

单独审计 ColorOS `OTA`/`cotad` 是否绑定跨机型 OTA；确认后再决定是否删除或禁用。不要和启动修复混在同一版。

## 6. 结论

当前 v36 不是“只差 WFD”的状态。WFD 是证据最强、改动最小的启动路径修正，v37 已完成；但相对 HyperOS 参考实现，仍有四类明确缺口：

1. **启动/框架相关**：SELinux audioserver/untrusted_app、USB UsbService、属性覆盖冲突。
2. **硬件声明相关**：light/context_hub/head_tracker/telephony.ims 假声明。
3. **显示/性能相关**：light-service、displayconfig/RRO、SF idle、GPU min_freq、模糊。
4. **安全/ABI 相关**：libutils/APEX VA guard，当前无匹配模式，不能套偏移。

建议先把 v37 作为 WFD 单变量实验保留；不要在 v37 上继续叠加 USB/framework/OTA 改动。下一步应优先做 v38 的策略与 feature 清理，再做显示/性能，最后处理 USB 和 libutils。