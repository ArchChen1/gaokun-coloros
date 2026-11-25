# 内核构建（ColorOS 移植 / gaokun3 / OPD2513）

目标不是"编一个能开机的内核"，而是**可复现、能给第三方重建**的内核镜像：别人拿这份文档 + 两个公开仓，能从 vanilla 7.2.9 走到和我们一模一样的状态。

当前已到达的状态：`7.2.9-gaokun3+`，136 个提交，HEAD `86450bb`（`media: i2c: hi846: Allow every analogue gain step`），能开机进桌面、`/dev/ublk-control` 开机即存在、相机与视频编解码在补齐，模块 ABI 与原厂 `.ko` 对齐。

## 一、基线与补丁来源（都是公开仓，pin 到具体提交）

| 来源 | 地址 | 用到的提交 | 作用 |
|---|---|---|---|
| 内核基线 | `git.kernel.org` tag `v7.2.9` | `2f6ee52` | vanilla 稳定树 |
| 构建层 | `github.com/KawaiiHachimi/linux-gaokun-buildbot` | `315528c` | EC/电池/面板 HX83121A/触摸/DSI-PLL/蓝牙/PDC 等 |
| 发版补丁池 | `github.com/vahiru/gaokun-android` | `230fa9a` | `patches/kernel/{drm,core,input,audio,iommu,camera,iris,fingerprint,ec-usb,...}` |
| 本仓自有补丁 | `coloros-port/config/kernel-abi-btf-fields.patch` | — | 让原厂 `.ko` 能加载（见第四节） |

内核树本身**不在本仓库里**（体积太大）。仓库只保存补丁清单、配置快照与构建脚本；完整树目前只存在于构建机的 `/home/cenmin/kbuild/linux-7.2.9-gk3`，那是唯一副本。

## 二、步骤 1–2：基线 + 构建层

```bash
tar xf linux-7.2.9.tar.xz -C ~/kbuild
cd ~/kbuild/linux-7.2.9 && git init && git add -A && git commit -m 'vanilla 7.2.9'
git am ~/kbuild/buildbot/patches/upstream/*.patch ~/kbuild/buildbot/patches/others/*.patch
```

踩过的坑，复现时会再遇到：

- `patches/upstream` 里第 7 个 pdc map 补丁与 7.2.9 上游已含内容冲突，判定"already introduced"后跳过。
- `others/0018`（pinctrl sc8280xp 不把 gpio175 映射到 PDC）与 `0007` 冲突。手改办法：删掉 `drivers/pinctrl/qcom/pinctrl-sc8280xp.c` 里的 `{ 175, 237 }` 那一项，再 `git am --continue`。
- `patches/media`（venus 系列）与 7.2.9 冲突，且只影响视频解码，**整组跳过**——编解码我们走 `iris`。
- `buildbot/0099-*.patch`（dts + defconfig 导入）放弃：它的 dts 与上游冲突，而我们只换内核 Image，dtb 仍用 ESP 里的原厂 `gaokun3.dtb`，不需要自己编 dtb。

## 三、步骤 3：应用发版补丁池

```bash
GAOKUN_SRC=~/gaokun-src bash coloros-port/scripts/kernel-apply-coloros.sh ~/kbuild/linux-7.2.9
```

清单在 `config/kernel-patch-manifest.txt`，是**我们实际打上的集合**，不是上游建议的集合：`drm` 19、`core` 6（0004–0009）、`fingerprint` 3、`ec-usb` 2（0011/0012）、`input` 22、`audio` 13、`iommu` 1、`camera` 35、`iris` 18，共 119 条。

脚本的 `--check` 在已经打满的树上会误报 FAIL（叠加补丁被后来的补丁改写了上下文，反向和正向 `--check` 都对不上，但树是对的）。要精确核对，用发版仓自带的 `gaokun-src/scripts/kernel-apply-patches.sh <tree> --verify`。

明确不打的：`dts` 24（改的是 `gaokun3-camera.dtsi` 这类拆分文件，7.2.9 树里是单文件 dts，打不上）、`wifi` 27（ath11k，本机走 qcacld）、`pcie-pm` 12、`core` 0001–0003（长尾，暂缓）。`camera/0005`、`0008`（hi846 曝光元数据）因基线漂移也打不上。

## 四、步骤 4：模块 ABI 对齐（关键，别漏）

原厂 vendor 里的 `.ko` 是给 `7.2.9-gaokun3+` 编的，且原厂配置 `CONFIG_MODVERSIONS`、`CONFIG_MODULE_SIG` 都是关的，所以只有两道关：vermagic 和 `struct module` 大小。

- `include/linux/module.h`：把被 `CONFIG_DEBUG_INFO_BTF_MODULES` 包住的 4 个字段（`btf_data_size` / `btf_base_data_size` / `btf_data` / `btf_base_data`）改成无条件存在，否则 `struct module` 会比原厂小，`this_module` 段尺寸对不上直接拒绝加载。见 `config/kernel-abi-btf-fields.patch`。
- `LOCALVERSION="-gaokun3"`，让 `scripts/setlocalversion` 在无 annotated tag 时自动补一个 `+`，最终 `make kernelrelease` = `7.2.9-gaokun3+`。踩过的坑：`LOCALVERSION` 自己带 `+` 会变成双加号；改完必须删 `include/config/auto.conf*` 再 `make syncconfig`，否则 `kernel.release` 是缓存值。

验证方式：`strings vmlinux | grep '7.2.9-gaokun3+ SMP'`，以及外部模块里 `_Static_assert(sizeof(struct module) == 1280, ...)`。

## 五、步骤 5：配置

```bash
cp coloros-port/config/kernel-config-7.2.9-gaokun3.txt .config
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
```

这份配置的来源是**设备实时的 `/proc/config.gz`**（原厂内核配置，2141 项），再定向改动。相对原厂必须显式开的项：

- `BLK_DEV_UBLK=y`、`BLKDEV_UBLK_LEGACY_OPCODES=y` —— VABC 的 userspace snapshot 全靠它，且必须内置（开机第一阶段就要有 `/dev/ublk-control`，模块在这时候还加载不了）
- `ASHMEM=y`、`NETFILTER_XT_MATCH_QUOTA2=y`
- `USB_ANDROID_USB_STATE=y`
- `GAOKUN3_FPCMD=y`、`TOUCHSCREEN_HIMAX_HX83121A_PEN=y`
- `V4L2_ISP=y`、`VIDEO_QCOM_CAMSS=y`、`VIDEO_QCOM_IRIS=y`、`VIDEO_QCOM_VENUS` 关闭、`VIDEO_HI846=y`、`VIDEO_OV13B10=y`、`VIDEO_DW9714=y`、`VIDEOBUF2_VMALLOC=y`
- `DEBUG_INFO_BTF` 及其 `_MODULES` 关闭（不走 pahole，避免工具链依赖）

## 六、步骤 6：构建

```bash
CPATH=~/ssl/usr/include:~/ssl/usr/include/x86_64-linux-gnu \
LIBRARY_PATH=~/ssl/usr/lib/x86_64-linux-gnu \
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) vmlinuz.efi
```

注意三点：产物要 **`vmlinuz.efi`**（裸 `Image` 没有 EFI stub，ESP 直接引导会失败）；不编 `dtbs`（dtb 用原厂）；`certs/extract-cert` 依赖 `libssl-dev`，没有 root 时装不了，就用本地解包的 ssl 头库走 `CPATH`/`LIBRARY_PATH`。

## 七、部署与回滚

只替换 ESP 里的内核，不动 dtb / ramdisk：

- 目标：`<ESP>:\476f1043c632e6862be1baca3ec17bba\android\slot_a\Image`
- 刷前必须备份当前 `Image`，刷后回读 sha256 与源文件比对
- 回滚：把备份拷回同一路径即可
- 原厂内核备份（18,743,808 B，sha256 `7854a013…9f47`）保留在构建机 `E:\gk3-coloros\work\bootwork\esp_Image_slot_a_orig.efi`

## 八、当前验证过的状态

- 冷启动 46 s 到 `sys.boot_completed=1`，`ro.boot.slot_suffix=_a`
- `uname -r` = `7.2.9-gaokun3+`，原厂 `.ko` 可加载
- `/dev/ublk-control`（`10,258`）、`/dev/ashmem`（`10,261`）开机即存在
- 显示、触摸、手写笔、外放验收通过

## 九、已知缺口

- **`dts` 那 24 条打不上**：需要内核升到已拆分 gaokun3 dtb 的上游（7.3/7.4），或手工移植到单文件 dts。目前靠原厂 dtb 的 `ovti,ov13b10` / `hynix,hi846` / `camss@ac5a000` 节点工作。
- **系统录音机不能用**：`AEC.AudioxService` 反复初始化失败，OPPO 那个效果库（UUID `41f6c0f4-…`）不在我们 `vendor/etc/audio_effects_config.xml` 里，属 userspace 缺库，与内核无关；第三方录音正常。
- `camera/0005`、`0008` 待手工移植。
- `ro.virtual_ab.ublk.enabled`、`ro.virtual_ab.userspace.snapshots.enabled` 目前是临时 `setprop`，重启即失，必须固化进镜像，否则 update_engine 回落到 legacy 路径。
