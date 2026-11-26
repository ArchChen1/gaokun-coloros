# 硬件编解码（v4l2 C2 HAL）现状与排查记录

> 2026-11-25。结论先行：**内核侧和用户态配置都齐了，缺的一环是 C2 HAL 服务根本没起来；补上之后仍不可用，暂搁置，主线转 OTA。** 恢复这项工作时按第 4 节的顺序取证据，不要凭猜。

## 1. 现状

内核（7.2.9-gaokun3+，HEAD `86450bb`，已含 `iris` 18 条 + `iommu` 1 条）：

- `CONFIG_VIDEO_QCOM_IRIS=y`，`VIDEO_QCOM_VENUS` 关。
- `/dev/video44 = qcom-iris-decoder`、`/dev/video45 = qcom-iris-encoder`（编号取决于 probe 顺序，不稳定）。
- camss 一家占了 `/dev/video0..43`（`msm_vfeN_videoM` 等），所以 iris 被推到高位。

用户态（vendor 镜像）：

- `/vendor/etc/media_codecs_c2.xml` 是 5 个组件：`c2.v4l2.avc.encoder`、`c2.v4l2.hevc.encoder`、`c2.v4l2.avc.decoder`、`c2.v4l2.hevc.decoder`、`c2.v4l2.vp9.decoder`。
- 门控属性全 true：`ro.vendor.v4l2_codec2.decoder.supported.{h264,hevc,vp9}`、`encoder.supported.{h264,hevc}`、`encode_concurrent_instances=1`；另有 `media.c2.hal.selection=aidl`、`debug.stagefright.c2-poolmask=0xfe0000`、`debug.stagefright.c2inputsurface=-1`。
- 扩展 seccomp 策略 `/vendor/etc/seccomp_policy/android.hardware.media.c2-extended-seccomp_policy` 在。
- `/vendor/lib64/libv4l2_codec2_{common,components,v4l2}.so` 在；没有任何 `c2.qti.*` 那套。

## 2. 已定位的缺口（已改，仍未解决）

`/vendor/etc/init/android.hardware.media.c2-service-v4l2.rc` 原文是：

```
service android-hardware-media-c2-v4l2-hal /vendor/bin/hw/android.hardware.media.c2-service-v4l2
    disabled
    class hal
    ...
```

`disabled` 且**没有 `interface aidl`** ⇒ init 永远不会按 lazy-start 拉起它，`class hal` 也不会（`disabled` 就是不随 class 起）。实测后果：

- binder 上只有 `android.hardware.media.c2.IComponentStore/software`（进程 `media.swcodec`），硬件用的 `/default` 不存在；
- `ps -A` 没有 `mediacodec`，`getprop init.svc.android-hardware-media-c2-v4l2-hal` 为空；
- `adb shell start ...` 回 `Must be root`（shell 无权 ctl.start）。

已把 rc 改成 `interface aidl android.hardware.media.c2.IComponentStore/default` 并去掉 `disabled`（脚本 `build/patch_vendor_c2_hal.sh`），原位写入 `vendor_a`，重启后**仍不可用**（用户验收）。所以"服务没起"是真缺口，但不是唯一缺口。

## 3. 为什么没走"把 iris 钉到 /dev/video10/11"

AOSP 的 `v4l2_codec2` 里 `V4L2Device::getDevicePathFor()` 存在固定 `10 + index*2` 的路径，一度打算把 `video10/11` 让给 iris。查 `vendor/gaokun-android/scripts/crdroid-tree-fixes.py`（修补 7）后否决：

- 上游已把 `V4L2Device::getDeviceInfosForType()` 的扫描上界 `video0..9` 放宽到 `kMaxVideoDeviceIndex = 64`，注释明确写"camss 占 32 个节点、编号随 probe 先后变，正解是放宽范围而不是钉死编号"；
- 我们这台的 `media_codecs_c2.xml` 与 `libv4l2_codec2_v4l2.so` 都是那套构建出来的，iris 在 44/45 应当能按名字找到；
- 把 `video10/11` 让出去要删掉 `msm_vfe1_video3` / `msm_vfe1_pix_params`，对相机有不可控风险，不值得为一次实验付这个代价。

## 4. 恢复排查的顺序（判据表）

直接用上游的验收脚本，它每一项都对应一个真实踩过的失败模式：

```bash
SERIAL=192.168.1.247:5555 bash vendor/gaokun-android/scripts/verify-hw-codec2.sh <某个.mp4>
```

六步与本机的对应：

| 步 | 看什么 | 本机的预期 |
|---|---|---|
| 1 | 门控属性、seccomp 策略文件 | 已全绿（见第 1 节） |
| 2 | `qcom-iris-decoder/encoder` 节点属主 `media:camera` | 属主已是 `media:camera` |
| 3 | `IComponentStore/default` 在不在、`c2-service-v4l2` 进程在不在、有没有 SIGSYS | **首要分叉点**；这次改完的结果还不知道 |
| 4 | `dumpsys media.player \| grep c2.v4l2.`：期望 3 解码 + 2 编码 | 若为 0，是 `V4L2ComponentStore` 没匹配到设备 |
| 5 | 真解一段 | 组件"在列表里"不等于能解 |
| 6 | `aa00000.video-codec` 报错、SMMU `SID=0x2a00/0x2e00` fault | 判断 iris UAPI 与这套组件有没有代差 |

三种可能的走向：

1. **服务一起来就崩**（crash loop / SIGSYS）→ 看 `logcat`，多半是 lib 依赖或 seccomp；再加 `debug.hwui` 无关，别被带跑。
2. **服务在、`/default` 在，但组件 0 个** → `V4L2ComponentStore` 没找到设备：核对它到底按名字扫还是按 `getDevicePathFor` 算；必要时再评估钉节点号。
3. **组件在、真解失败** → mainline iris 的 UAPI 与这套 venus 风格组件有代差，属于内核/用户态联调活；这也解释了为什么相机能拍却录不了。

## 5. 这次的写回方式（可复用）

不重出 super，只按 extent 原位写 `vendor_a`：

| 项 | 值 |
|---|---|
| super 分区 | disk 0 / partition 10，offset `344101748736`（0x501E100000），20 GiB |
| `vendor_a` 在 super 内 | sector `4478976`（`work/lpdump_now.txt`），1048576 sectors |
| 绝对偏移 | `346394984448`（0x50A6C00000），长度 536,870,912 B |
| 写前校验 | 该位置前 4 MiB sha256 必须 == 基座 `48197eb2…9edaa5`，且 `+1024` 处是 ext4 magic `0xEF53` |
| 工具 | `tools/vendor_extent_write.ps1`（默认只校验+备份，`-Write` 才写，`-Restore` 回滚） |
| 原始备份 | 平板 `C:\gk3work\vendor_a_backup.img`（sha `5a5853c5…2e82`，等于 `vendor.img.pre_c2`） |
| 回读校验 | 写后读回前 64 MiB 与镜像比对 |

备份 sha 与 `parts/vendor.img.pre_c2` 完全一致，等于"设备上那块就是这个基座"，所以写回是可逆的。

## 7. 2026-11-27 定位到真因：odm 的 libui 遮蔽了 vendor 的 libui

第 2 节把 rc 修好之后服务仍起不来，这次抓到了确切原因，**不是内核、不是 seccomp、也不是组件匹配**。

### 7.1 现象

```
F linker : CANNOT LINK EXECUTABLE "/vendor/bin/hw/android.hardware.media.c2-service-v4l2":
  cannot locate symbol "_ZN7android19GraphicBufferMapper15setSmpte2094_50E…"
  referenced by "/vendor/lib64/libcodec2_vndk.so"
```

`init.svc.android-hardware-media-c2-v4l2-hal = restarting`，每 5 s 崩一次；
binder 上只有 `IComponentStore/software`，`dumpsys media.player` 里 `c2.v4l2.*` 一个都没有。
门控属性、iris 节点属主（`media:camera`）、扩展 seccomp 策略全部是绿的。

### 7.2 真因

`GraphicBufferMapper::setSmpte2094_5` 由 `libui.so` 提供。设备上有四份 libui：

| 路径 | 大小 | 来源 | 有 setSmpte2094_5 |
|---|---|---|---|
| `/odm/lib64/libui.so` | 480,760 | ColorOS 自带 | **没有** |
| `/vendor/lib64/libui.so` | 444,592 | crDroid 构建 | 有 |
| `/system/lib64/libui.so` | 436,360 | ColorOS 自带 | 有 |
| composer apex | 461,016 | ColorOS 自带 | 有 |

而 `/linkerconfig/ld.config.txt` 的 `[vendor]` 段：

```
namespace.default.search.paths  = /odm/${LIB}
namespace.default.search.paths += /vendor/${LIB}
```

**odm 排在 vendor 前面**。于是 crDroid 编的 `libcodec2_vndk.so` 绑到了 OPPO 那份旧 libui 上，
缺一个符号，整个可执行文件链接失败。三份 libui 的 `.gnu.hash` 都查过，不是哈希表的问题。

### 7.3 为什么不换掉 odm 的 libui

量过：odm libui 导出 770 个符号、vendor 564 个，odm 独有的 253 个**全是 WEAK 模板实例与 vtable**，
强符号（GLOBAL FUNC/OBJECT）独有数为 **0**。所以纯从符号看换掉是安全的。

但 odm 那份被显示、相机等所有 vendor HAL 共用，两份 libui 明显不是同一 AOSP 快照
（vendor 侧多出 `DependencyMonitor`、`PictureProfileHandle`、`getStride` 等较新的 API），
换掉等于给整条图形栈换底座，风险不可控。**否决。**

### 7.4 采用的修法：把那一个引用改成 WEAK

`build/patches/p_codec_libui_weak.py` + `build/patch_vendor_codec_libui.sh`：
把 `libcodec2_vndk.so` 的 `.dynsym[56]` 的 `st_info` 由 `0x12`(GLOBAL) 改成 `0x22`(WEAK)，
**只动 1 字节**，文件长度、权限、属主、`vendor_file` 标签都不变。
bionic 对未解析的 WEAK 符号放行（GOT 置 0），对 GLOBAL 才报 cannot locate symbol。

支撑这个修法的三条实测：

1. **整个 C2 闭包只缺这 1 个符号**。逐库核对 HAL 本体、`libcodec2_{vndk,aidl,hal_common}`、
   `libv4l2_codec2_{common,components,v4l2}` 对 libui 域符号的引用；
   另外几个 `android::ColorUtils::*` 是 `libstagefright_foundation.so` 提供的，不缺。
2. **该符号在库里只有 1 处调用**（`llvm-objdump-18` 反汇编，0x5aeac），
   位于一个内部的 HDR 动态元数据写入函数（构造 `optional<vector<uint8_t>>` 后调用），
   `libcodec2_vndk` 没有导出任何 Smpte2094_5 相关 API。
3. **三个 v4l2 组件库对 Smpte2094 的引用数都是 0** —— 这条路根本走不到。
   iris 只吃 8 位 NV12，没有 HDR 编解码。

风险边界：万一将来有组件真的走到这条路，会跳到空指针，**只崩 C2 HAL 这一个进程**，
不影响显示与相机；回滚就是把 vendor 换回 `dd574c17…`。

### 7.5 产物

- `work/parts_codec/vendor.img` 536,870,912 B（尺寸不变），
  sha `6fa870afb7c173d5f3771e0ba83fefa6bbb24f391f8ae37d648a87a07187821c`，e2fsck clean。
- 增量包 `work/payload_codec_delta/`：**308 MiB**（vendor 128 ops + 其余 12 分区各 1 条 SOURCE_COPY），
  离线重拼 8.95 GiB 全对（`PAYLOAD_VERIFY_PASSED`）。
- 源账本 `work/manifest-src-codec.json`（vendor 回退为 `dd574c17…`）。

### 7.6 刷入后要验的

链接成功只是第一关，第 4 节那张判据表仍然要走完：
`IComponentStore/default` 在不在 → `dumpsys media.player` 是不是 3 解码 + 2 编码 →
真解一段 → 真编一段（`screenrecord --codec-name c2.v4l2.avc.encoder`，要亮屏）。
本机没有 root，读不到 dmesg，`cp-nonpixel: CB15 ready` 与 iris 报错这两项只能记为跳过。

## 8. VINTF 未声明导致注册被拒（已修，2026-11-27）

### 8.1 现象与取证

WEAK 补丁刷入后 `CANNOT LINK` 消失、HAL 常驻，但 `IComponentStore/default` 仍 not found。
取证卡在日志：本机 main 缓冲默认 **256 KiB**，ColorOS 日志量下只能存约 13 秒，
HAL 在开机 16.7 s 启动的日志早被冲掉；`logcat -G` **重启即复原**。
最后设 `persist.logd.size=32M`（可持久，调试用，可随时删）才盖住开机段，拿到：

```
D Instantiating Codec2's V4L2 IComponentStore service...
E Cannot register Codec2's IComponentStore service with instance name
  "android.hardware.media.c2.IComponentStore/default"
```

**中间没有 `Cannot create`** ⇒ `V4L2ComponentStore::Create()` 成功、设备节点已找到，
只有 `addService` 被拒。`getenforce` = Permissive，排除 SELinux。

### 8.2 真因与修法

全盘扫 vintf 目录，声明 `android.hardware.media.c2` 的只有
`/system/etc/vintf/manifest/manifest_media_c2_software.xml`（软解，type=framework），
**vendor 侧一个分片都没有**。servicemanager 对 vendor 进程注册 AIDL 服务要校验 VINTF 声明。

补 `/vendor/etc/vintf/manifest/android.hardware.media.c2-service-v4l2.xml`：
`format="aidl"` / `version=1`（HAL 链 `android.hardware.media.c2-V1-ndk.so`）/
`fqname=IComponentStore/default`，属主权限标签照现有 thermal 分片。
脚本 `build/patch_vendor_c2_vintf.sh`，产物 vendor sha `7b571d63…`（尺寸不变）。

刷入后：`service registered` 日志出现、`service check` found、
`Codec2Client: Available Codec2 services: "default" "software" "__ApexCodecs__"`。

## 9. odm 空壳 media_codecs_c2.xml 遮蔽 vendor 清单（已修，2026-11-27）

### 9.1 现象

注册过了，组件仍 0 个。框架日志：

```
Codec2InfoBuilder: component 'c2.v4l2.avc.decoder' not found in xml
MediaCodecsXmlParser: parsing /odm/etc/media_codecs_c2.xml...
```

`/vendor/etc/media_codecs_c2.xml`（6904 B，5 个组件）**从未被打开**。

### 9.2 真因

`searchMediaCodecsXmlPath` 按 `/odm/etc` → `/vendor/etc` → `/system/etc` 找同名文件，
**命中第一个就停**。OPPO 在 odm 放了 791 B 空壳，全文只有 `<Included></Included>`，
零条声明 ⇒ codec map 为空 ⇒ HAL 枚举出的组件全被 `Codec2InfoBuilder.cpp:543` 跳过。
软解不受影响，因为它走的是另一个文件名（APEX 的 `media_codecs.xml`），两条搜索互不干扰。

**这是本项目第二次踩 odm 遮蔽 vendor**（第一次是第 7 节的 `libui.so`）。
以后凡涉及同名文件，先查 `/odm` 有没有同名件。

### 9.3 修法与产物

删掉那个空壳（不选"把 vendor 内容拷进 odm"，那会留下改 vendor 永不生效的坑）。
脚本 `build/patches/p_odm_drop_empty_c2_xml.sh`，闸门包括：删前把当前镜像解包与树逐条 diff 必须为 0、
被删文件必须是 791 B 且无声明、重打后该文件不在镜像里、充电两个 so 仍在、UUID 保持、
解包回比差异必须正好是少了这一个文件。
产物 odm sha `e8856c58…`（2,131,329,024 B 不变），增量 1.98 GiB / 44.7 s / rc=0。

⚠️ `dump.erofs --path=<不存在的路径>` **也返回 0**（只打 `<E> read inode failed`），
判存在与否必须看输出里有没有 `regular file`，不能看退出码。

### 9.4 验收结果

- **组件齐了**：`c2.v4l2.{avc,hevc,vp9}.decoder` + `c2.v4l2.{avc,hevc}.encoder`，
  3 解码 2 编码，`owner: codec2::default`、`hw-accelerated: 1`、`rank: 128`。
  解析路径已变成 `parsing /vendor/etc/media_codecs_c2.xml`。
- **硬解通过**：HAL 侧走完完整周期 `Idle => Decoding => Draining => Idle`，
  实测分辨率 1920x1088、1152x416、3072x1280；HEVC 有 `merged 89 B CSD + 129501 B frame`。
- **硬编未通**：`screenrecord --codec-name c2.v4l2.avc.encoder` rc=0 但
  `recorded 0 frames`，mp4 的 `mdat` 长度为 1、时长 0。真因在 HAL：

  ```
  V4L2Device: (OUTPUT_MPLANE)Failed to set format (format_fourcc=0x32314d4e)
  ```

  `0x32314d4e` = `'NM12'` = `V4L2_PIX_FMT_NV12M`（**多平面** NV12），
  而 iris 只收单平面 `NV12`（枚举时那两条 `Unhandled pixelformat NV12 / Q08C` 也是同一处不认）。
  对应上游 `patches/android/v4l2-codec2/0006`（单平面输入按驱动 `sizeimage` 给长度）
  及其配套的格式选择改动 —— **我们这份 C2 二进制没带上游那批补丁**。
- 无 root，CB15 与 iris 内核报错两项仍记为跳过。
- 本机没有 `/system/bin/gaokun3-decode-test`，真解改用第三方 App 触发 + HAL 日志判定。

### 9.5 硬编下一步

要通硬编，只能回到上游那套打满补丁的 `external/v4l2_codec2` 重新构建
（`patches/android/v4l2-codec2/0001..0006`），而不是继续在 vendor 里缝二进制。
相机录像依赖硬件编码器，此项不解决录像就不完整。

## 10. 遗留待办

- 若链接修好后组件仍为 0 或真解失败，候选是回到上游那套打满补丁的 `external/v4l2_codec2` 构建（修补 3/5/7 + `patches/android/v4l2-codec2/0001..0006`），而不是继续在 vendor 里缝。
- 相机录像依赖硬件编码器，本项不解决，录像功能就不完整；相机"官方 App 打不开"是另一个问题（provider 只枚举到 1 个后摄，官方 App 取前摄 characteristics 拿到 null 触发 NPE，第三方相机可用）。
