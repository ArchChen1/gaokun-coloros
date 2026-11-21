# v43 全面静态差异审计与闭合记录

日期：2026-11-22

## 1. 结论

这次不是只改 WFD，也不是只补一两个 HAL。审计覆盖了 HyperOS 参考仓库
`analysis/matebookego_hyperos` 中 `scripts/build.py`、`scripts/configure_display.py`、
`scripts/overlay.py`、`scripts/patch_xiaomi_va_os4.py`、`assets/` 和
`CHANGES.md` 记录的构建变更，并与 ColorOS v42 的实际启动日志和 v43 分区内容逐项对照。

v43 最终静态策略包含：

- 保留并验证 SurfaceFlinger 的 4 处 `waitForService -> checkService` 补丁；
- 32 位 ABI / `zygote64_32` / 240 DPI 统一；
- WFD 关闭，Wi-Fi Direct 声明不再参与启动路径；
- light-service 亮度算法补丁；
- displayconfig；
- HyperOS 等价的 SF idle / 120 Hz / GPU 最低频策略（启动完成后）；
- 缺失硬件特性统一 `unavailable-feature`；
- 删除/禁用 v42 日志中确认无法链接或反复重启的 ODM HAL；
- 禁用 ABI 不匹配的 v4l2 Codec2 HAL；
- 隔离 IMS、Find My provider、Cota、RomUpdate、OplusBootReg；
- 删除旧的 v29–v36 日志采集器和 v38r3/v40 探针；
- 保留 SELinux permissive 作为 bring-up 阶段的安全网，但不把 permissive 当成修复。

尚未完成或冻结的项：

- `services.jar` 的 USB `/sys/class/android_usb -> /sys/class/udc` 修改：v33 注入已失败，继续冻结；
- APEX 内 `libutils` VA guard：当前 ColorOS 二进制没有 HyperOS 的旧指令模式，不能盲套；
- ColorOS 专用 framework RRO：本次只落 displayconfig，不直接复用 HyperOS 的 RRO APK；
- 运行时 `sys.boot_completed=1` 尚未验证；必须刷入后从 metadata 和 logcat 确认。

## 2. 审计对象与方法

### HyperOS 参考

```text
E:\gaokun-coloros\analysis\matebookego_hyperos
```

参考架构：

- 小米 Pad 9 HyperOS 底包 + crDroid/gaokun vendor；
- framework/service 修改绑定 MIUI 类名，不能直接搬到 ColorOS；
- 可复用的是硬件适配类：属性、HAL/VINTF、显示、音频、SELinux、图形库、诊断策略。

### ColorOS 当前对象

v43 分区：

```text
/home/cenmin/coloros-build/v43/system-v43.erofs
/home/cenmin/coloros-build/v43/system_ext_v43.erofs
/home/cenmin/coloros-build/v43/product_v43.erofs
/home/cenmin/coloros-build/v43/vendor_a_v43.img
/home/cenmin/coloros-build/v43/odm_v43.erofs
/home/cenmin/coloros-build/v43/my_product_a_v43.erofs
/home/cenmin/coloros-build/v43/my_stock_a_v43.erofs
```

v42 运行日志：

```text
E:\gaokun-coloros\analysis\v42-run-logs
```

限制：

- 没有 USB ADB，不能依赖 `adb shell`；
- 只能通过 metadata 分区、pstore/dmesg 快照和离线挂载取证；
- HyperOS 仓库没有最终 super 镜像，因此做的是“已记录变更集 vs ColorOS 实际分区”的映射，不是两个最终 super 的逐字节 diff；
- 当前 `checkvintf` 主机工具不能解析 manifest.version 9.0，VINTF 结论来自 XML、文件、init rc 和 ELF NEEDED 的静态检查。

## 3. v42 已经证明的失败点

v42 的 3/10/30/60 秒快照显示系统没有到达 `sys.boot_completed=1`。主要证据：

```text
SurfaceFlinger: trackPendingFrame: Invalid present fence
HWUI: drawRenderNode called on a context with no surface!
```

以及反复出现的链接失败：

```text
/vendor/bin/hw/android.hardware.media.c2-service-v4l2
  cannot locate GraphicBufferMapper::setSmpte2094_50
/odm/bin/hw/dvs-aidl-service
  android.hardware.sensors-V3-ndk.so not found
/odm/bin/hw/vendor-oplus-hardware-touch-V2-service
  libhidltransport.so not found
/odm/bin/hw/vendor.oplus.hardware.cryptoeng@1.0-service
  libqmi_cci.so not found
/odm/bin/hw/vendor.oplus.hardware.charger-V12-service
  libjsoncpp.so not found
/odm/bin/hw/vendor.oplus.hardware.displaypanelfeature-service
  libqservice.so not found
/odm/bin/nvram_qmi
  libqmi_common_so.so not found
/odm/bin/hw/mdm_feature
  libxml2.so not found
```

此外：

- `com.qti.phone` 进程中的 `org.codeaurora.ims.ImsService` 持续崩溃；
- `com.coloros.bootreg` 和 SystemUI 因没有有效 surface 反复 abort；
- `ro.zygote=zygote64`，而 HyperOS 实机为 `zygote64_32`；
- `ro.sf.lcd_density=420`，而 HyperOS 实机为 240。

这些是 v43 静态清理的直接依据。

## 4. HyperOS 变更项到 ColorOS 的完整映射

状态说明：

- DONE：v43 已做等价实现；
- PARTIAL：做了但还需要运行时确认；
- N/A：HyperOS 包名/类名不适用于 ColorOS；
- BLOCKED：当前证据不足，不能安全照搬。

| 子系统 | HyperOS 参考动作 | ColorOS v43 | 结论 |
|---|---|---|---|
| WFD | `persist.debug.wfd.enable=0`，不靠 Wi-Fi Direct 让 WFD 注册 | system/vendor/odm 均置 0，删除 Wi-Fi Direct 声明 | DONE |
| 图形库 | 用 crDroid/gaokun 图形库替换 ANGLE/EGL 相关库 | v5 起已替换，v43 保留并验证 `libEGL.so` 无 kgsl 依赖 | DONE |
| SELinux ashmem | audioserver / untrusted_app 的 ashmem 基础域规则 | v38 起已合并，v43 保留 | DONE |
| libutils VA guard | system/product/gsid 及 APEX 内 libutils 按 56 位地址上界修补 | ColorOS 当前二进制没有 HyperOS 的 `b2409be8/b240bbe9` 模式 | BLOCKED |
| USB framework | UsbService 的 `/sys/class/android_usb` 改为 `/sys/class/udc` | v33 注入失败，v43 不改 services.jar | BLOCKED/冻结 |
| 32 位 zygote | `ro.zygote=zygote64_32`，补 32 位 ABI | system/vendor/odm/my_product 统一，确认 `app_process32`、`system/lib` 存在 | DONE |
| 密度 | 240 基准，用户显示大小另设 | 所有 build.prop 统一 240；启动完成后再执行 `wm density 320` | DONE/PARTIAL |
| light-service | BACKLIGHT 从 RGB Rec.601 加权改为 state.color 低字节 | 在 ColorOS 当前二进制偏移 `0x393d4` 打入 `0x39400048` | DONE |
| displayconfig | 1600×2560、240 DPI、亮度映射 | product 增加 default.xml/display_id_0.xml | DONE |
| SF idle/刷新率 | idle/touch timer、frame-rate override、120 Hz 设置 | v41 参数保留，v43 启动完成后写 settings | DONE/PARTIAL |
| GPU 最低频 | boot_completed 后写 690000000 | system/vendor rc 均加入 | DONE/PARTIAL |
| 背景模糊 | 关闭 SF/HWUI 模糊 | build.prop + rc 关闭 | DONE |
| 缺失特性 | 添加 unavailable-feature：ALS、指南针、GPS、电话、NFC | vendor 增加完整 XML，并移除 my_product 光感声明 | DONE |
| FindDevice provider | 禁用 `FindDeviceStatusManagerProvider` | 禁用 ColorOS 对应 `com.oplus.find.provider.FindProvider` | DONE/需运行时确认 |
| ThermalService | 禁用小米 `com.miui.powerkeeper.thermal.ThermalService` | ColorOS 未找到同名类；保留 gaokun3 vendor thermal HAL，避免误禁 | N/A/保留 |
| OTA/Updater | 删除 Xiaomi Updater/miupdater | 删除 system_ext OTA/cotad，删除 my_stock Cota/RomUpdate | DONE |
| OplusBootReg | 不属于 HyperOS，但会触发 ColorOS 首启流程 | 删除 my_stock OplusBootReg，保留 /etc/bootreg 资源 | DONE |
| IMS | 无直接 HyperOS 项；ColorOS donor IMS 无 modem | 删除 system_ext ims/ImsDataChannelService，禁用 ImsService | DONE |
| VINTF/HAL | 只保留 gaokun 可用的 HAL | 删除/禁用 displaypanel、dvs、cryptoeng、charger、touch、nvram、mdm、media v4l2 | DONE |
| 音频 VINTF | 移除缺失 binaural/virtual audio 声明 | v23/v24 已处理，v43 保留 | DONE |
| 诊断日志 | HyperOS 有 bootlog 方案，但本项目已证明常驻采集器路线不可用 | 删除 gk3-capture、v38r3/v40 探针，只保留 boot_completed marker | DONE/策略变更 |
| ColorOS framework RRO | HyperOS 有 Gaokun3FrameworkOverlay.apk | 未直接复用，避免 ColorOS 资源命名冲突 | 保留为后续项 |

## 5. v43 最终静态改动

### 5.1 system

```text
ro.zygote=zygote64_32
ro.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi
ro.product.cpu.abilist32=armeabi-v7a,armeabi
ro.product.cpu.abilist64=arm64-v8a
ro.radio.noril=true
ro.adb.secure=0
ro.mediaserver.64b.enable=true
ro.surface_flinger.supports_background_blur=0
persist.sys.background_blur_supported=false
persist.debug.wfd.enable=0
persist.sys.usb.config=adb
persist.adb.tcp.port=5555
persist.sys.disable_rescue=true
debug.sf.auto_latch_unsignaled=1
```

新增：

```text
/system/etc/init/gaokun3-v43.rc
/system/etc/gaokun3-postboot.sh
/system/etc/sysconfig/gaokun3-components.xml
```

`gaokun3-components.xml` 现在针对正确包名：

```xml
<component-override package="org.codeaurora.ims">
  <component class="org.codeaurora.ims.ImsService" enabled="false" />
</component-override>
<component-override package="com.coloros.findmyphone">
  <component class="com.oplus.find.provider.FindProvider" enabled="false" />
</component-override>
```

注意：v42 日志里的 `com.qti.phone` 是进程名，不是 IMS APK 的包名；IMS APK 的包名是
`org.codeaurora.ims`。旧版本把 override 写成 `com.qti.phone` 是无效的，v43 已纠正。

SurfaceFlinger 保留 4 处补丁，补丁后 SHA256：

```text
44482c704adf3f661f688695a37655150bc8c4851b360a06f0ffb03beb73dcac
```

### 5.2 system_ext

删除：

```text
priv-app/ims
app/ImsDataChannelService
app/OTA
bin/cotad
bin/imsvtdaemon
etc/init/cotad.rc
etc/init/imsvtdaemon.rc
etc/permissions/vendor.qti.imsdatachannel.xml
etc/permissions/vendor.qti.imsdcservice.xml
```

### 5.3 product

新增：

```text
/product/etc/displayconfig/default.xml
/product/etc/displayconfig/display_id_0.xml
```

内容为 1600×2560、240 DPI、亮度 0.04–1.0 的名义映射。

### 5.4 vendor

新增：

```text
/vendor/etc/permissions/gaokun3-unavailable-features.xml
```

声明缺失：

```text
android.hardware.sensor.light
android.hardware.sensor.compass
android.hardware.location.gps
android.hardware.telephony
android.hardware.telephony.gsm
android.hardware.telephony.cdma
android.hardware.telephony.ims
android.hardware.nfc
```

删除/禁用：

```text
android.hardware.media.c2-service-v4l2.xml      删除 VINTF
android-hardware-media-c2-v4l2-hal              disabled
gk3-capture.rc / gk3-capture.sh                 删除
v38r3_dump.sh / v40_dump.sh                     删除
smmustall.rc 中的 gk3-capture service            删除
init.gaokun3.rc 中的 v38r3/v40 on-property 块   删除
```

保留：

```text
vendor.thermal-gaokun3
vendor.sensors-gaokun3
vendor.graphics.allocator
vendor.fingerprint-gaokun3
vendor.boot-gaokun3
```

light-service：

```text
原 SHA256 3f1690d396e9269f699f37781074e75f7db000b71abc3db10554fa02b56fca13
偏移     0x393d4
原指令   53087d08
新指令   39400048
新 SHA256 e02556898c6ba10ed41080b76425b43a11f14dfe492dbb8bfd0492f70f8257dc
```

### 5.5 odm

统一：

```text
ro.zygote=zygote64_32
ro.sf.lcd_density=240
Huawei / MateBook E Go / gaokun3
ro.product.oplus.cpuinfo=SC8280XP
```

删除无效 VINTF/permission XML，并禁用：

```text
displaypanelfeature-service
dvs-aidl-service
hal_cryptoeng_oplus
oplus_charger_hal_service
vendor.touch-aidl-1
nvram_qmi
nvram_diag
mdm_feature 相关 oneshot 服务
```

删除 `engineer_vendor_shell.sh addRadioFile` 启动行。

### 5.6 my_product

统一密度/zygote/身份和 USB ADB 属性，删除 donor `supported_versions`、
`authentication` 标记，删除残留的：

```text
etc/permissions/android.hardware.sensor.light.xml
```

### 5.7 my_stock

删除：

```text
priv-app/OplusBootReg
priv-app/Cota
app/RomUpdate
```

保留 `etc/bootreg` 资源目录，避免误删 bootreg 图片/JSON 资源。

## 6. 静态验证结果

已验证：

- super 内 13 个分区与构建分区逐字节一致；
- system/system_ext/product/odm/my_product/my_stock 通过 `fsck.erofs`；
- vendor 通过 `e2fsck -fn`；
- SurfaceFlinger 哈希固定；
- light-service 哈希和指令固定；
- 32 位 `app_process32`、`system/lib`、`system/lib64` 存在；
- 所有关键 build.prop 的 zygote/密度一致；
- WFD=0，Wi-Fi Direct XML 不存在；
- IMS/OTA/Cota/RomUpdate/OplusBootReg 不存在；
- media v4l2 VINTF 不存在且 service 为 disabled；
- 旧采集器和 v38r3/v40 探针不存在；
- displayconfig 存在；
- `gaokun3-unavailable-features.xml` 的 SELinux xattr 已设置。

当前构建指纹（以最终 release 文件为准）：

```text
system-v43.erofs          30f1e925f2c08fda6ac7f24c463354d43c9ee5998f46c536745c1a23d5e02062
system_ext_v43.erofs      5c25dfa5a9673591d68a7fcafe3c93d71125a4751bab8e9c2af4fb1a5389ca23
product_v43.erofs         65c1e5218413e80b2b17252fe571f307e3f66181de1fa354565aa138e2d44cf0
vendor_a_v43.img          f1e93adfe0fdf5aaa54f2fe1f6bf28bfaeaeb594bdf912d6d568bc7b7b8cea5c
odm_v43.erofs             302de8084fed08e79a8b7c2fc87e3736988b1e0d0ce7ad2da0c6031e7cc5f278
my_product_a_v43.erofs    d9ebe4fe5b97f8acf987389ead23508579a672afbbbc0495403fc181fcfba71a
my_stock_a_v43.erofs      f33b154441ff6abd0978c5c01cb58d6d499f6c38de63c4f517aa25f2d66f2c3b
super-coloros-v43.simg    369218ba4eb8de1b20e2b637b712ce06d7035b7859f73075cf3be234aa99b0a9
release super.img.zst     83c536335df9e60e4319b535a8830ce0680a94b8f52f25f7daba72d335cf81f9
boot.img                  ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
```

旧 v43 release（light-service 补丁前）的 `super.img.zst` 哈希 `966afe...` 已失效，不要使用。

## 7. 为什么没有直接复制 HyperOS 的 framework/RRO

HyperOS 的 `Gaokun3FrameworkOverlay.apk` 针对 MIUI framework 资源，包含：

- 亮度最小/最大/默认值；
- 无刘海、矩形屏幕；
- AOD/ALS 关闭；
- 120 Hz 默认值；
- 状态栏高度等。

ColorOS 的 framework 资源名和资源表与 MIUI 不同。直接复制可能造成：

- RRO 资源名不匹配；
- 静态 overlay 编译/签名失败；
- 覆盖 ColorOS 自身显示策略，反而引入新的 SurfaceFlinger 问题。

因此 v43 只做可验证的 `displayconfig` 和属性策略。ColorOS 专用 RRO 应等
`sys.boot_completed=1` 后，用 `aapt2 dump resources` 对 ColorOS framework-res
重新生成，而不是复用 HyperOS APK。

## 8. 刷机与首次启动

安装器会重置 ESP。刷完 Android 分区后、首次启动前，必须在 EGO 的管理员 PowerShell 执行：

```powershell
powershell -ExecutionPolicy Bypass -File D:\cos\set-esp-permissive-after-install.ps1
```

确认 ESP 参数包含：

```text
androidboot.selinux=permissive
loglevel=7
```

然后再启动 Android。

## 9. 失败时的取证顺序

不要恢复常驻采集器。按以下顺序做一次性取证：

1. 回到 Windows，运行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File D:\cos\grab-v43-metadata.ps1
   ```

2. 拉回 `metadata-v43run.img`，在副本上执行 `e2fsck -fy`，只读挂载。

3. 检查：

   ```text
   /metadata/gk3-boot-completed-marker
   /metadata/gk3-v36... 或 v40 相关 marker（如果仍存在）
   ```

4. 从 pstore/dmesg/logcat 快照检查：

   ```text
   sys.boot_completed
   Invalid present fence
   drawRenderNode called on a context with no surface
   CANNOT LINK EXECUTABLE
   org.codeaurora.ims / ImsService
   com.coloros.bootreg
   SurfaceFlinger / HWUI abort
   ```

5. 如果 boot_completed 仍为 0，优先判断是：
   - SurfaceFlinger/HWUI 仍未拿到有效 surface；
   - 另一个 donor HAL 在链接/启动阶段崩溃；
   - ColorOS framework 仍等待某个 OPlus 服务；
   - 而不是继续加日志服务。

## 10. 仍需运行时确认的项目

- `ro.zygote` 实际是否为 `zygote64_32`；
- `ro.sf.lcd_density` 实际是否为 240；
- `ro.radio.noril` 是否生效；
- `gaokun3-unavailable-features.xml` 是否被 PackageManager 读取；
- FindProvider override 是否阻止 Find My 在首启阶段拉起；
- light-service 是否正常启动且背光不骤黑；
- media v4l2 禁用后是否有可用的软件 Codec2 回退；
- `sys.boot_completed=1` 是否最终出现；
- SystemUI/bootreg 是否还有 `drawRenderNode ... no surface`。

这些只能通过 v43 实机启动确认，静态检查不能替代。
