# 内核构建（ColorOS 移植 / gaokun3 / OPD2513）

目标不是"编一个能开机的内核"，而是**可复现、能给第三方重建**的内核镜像：别人拿这份文档 + 两个公开仓，能从 vanilla 7.2.9 走到和我们一模一样的状态。

当前已到达的状态：`7.2.9-gaokun3+`，136 个提交，HEAD `86450bb`（`media: i2c: hi846: Allow every analogue gain step`），能开机进桌面、`/dev/ublk-control` 开机即存在、相机与视频编解码在补齐，模块 ABI 与原厂 `.ko` 对齐。

## 一、基线与补丁来源（都是公开仓，pin 到具体提交）

| 来源 | 地址 | 用到的提交 | 作用 |
|---|---|---|---|
| 内核基线 | `git.kernel.org` tag `v7.2.9` | `2f6ee52` | vanilla 稳定树 |
| 构建层 | `github.com/KawaiiHachimi/linux-gaokun-buildbot` | `315528c` | EC/电池/面板 HX83121A/触摸/DSI-PLL/蓝牙/PDC 等 |
| 发版补丁池 | `github.com/vahiru/gaokun-android` | `230fa9a` | `patches/kernel/{drm,core,input,audio,iommu,camera,iris,fingerprint,ec-usb,...}` |
| 本仓自有补丁 | `patches/kernel-build/kernel-abi-btf-fields.patch` | — | 让原厂 `.ko` 能加载（见第四节） |

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
GAOKUN_SRC=~/gaokun-src bash build/kernel_patches.sh ~/kbuild/linux-7.2.9
```

清单在 `patches/kernel-build/kernel-patch-manifest.txt`，是**我们实际打上的集合**，不是上游建议的集合：`drm` 19、`core` 6（0004–0009）、`fingerprint` 3、`ec-usb` 2（0011/0012）、`input` 22、`audio` 13、`iommu` 1、`camera` 35、`iris` 18，共 119 条。

脚本的 `--check` 在已经打满的树上会误报 FAIL（叠加补丁被后来的补丁改写了上下文，反向和正向 `--check` 都对不上，但树是对的）。要精确核对，用发版仓自带的 `gaokun-src/scripts/kernel-apply-patches.sh <tree> --verify`。

明确不打的：`dts` 24（改的是 `gaokun3-camera.dtsi` 这类拆分文件，7.2.9 树里是单文件 dts，打不上）、`wifi` 27（ath11k，本机走 qcacld）、`pcie-pm` 12、`core` 0001–0003（长尾，暂缓）。`camera/0005`、`0008`（hi846 曝光元数据）因基线漂移也打不上。

## 四、步骤 4：模块 ABI 对齐（关键，别漏）

原厂 vendor 里的 `.ko` 是给 `7.2.9-gaokun3+` 编的，且原厂配置 `CONFIG_MODVERSIONS`、`CONFIG_MODULE_SIG` 都是关的，所以只有两道关：vermagic 和 `struct module` 大小。

- `include/linux/module.h`：把被 `CONFIG_DEBUG_INFO_BTF_MODULES` 包住的 4 个字段（`btf_data_size` / `btf_base_data_size` / `btf_data` / `btf_base_data`）改成无条件存在，否则 `struct module` 会比原厂小，`this_module` 段尺寸对不上直接拒绝加载。见 `config/kernel-abi-btf-fields.patch`。
- `LOCALVERSION="-gaokun3"`，让 `scripts/setlocalversion` 在无 annotated tag 时自动补一个 `+`，最终 `make kernelrelease` = `7.2.9-gaokun3+`。踩过的坑：`LOCALVERSION` 自己带 `+` 会变成双加号；改完必须删 `include/config/auto.conf*` 再 `make syncconfig`，否则 `kernel.release` 是缓存值。

验证方式：`strings vmlinux | grep '7.2.9-gaokun3+ SMP'`，以及外部模块里 `_Static_assert(sizeof(struct module) == 1280, ...)`。

## 五、步骤 5：配置

```bash
cp patches/kernel-build/kernel-config-7.2.9-gaokun3.txt .config
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

## 十、补丁账本与校验（2026-11-26 起）

内核这一层以前只活在构建机的 git 里，出了这台机器就没人能证明"补丁还在"。现在和分区补丁用同一套规矩：

| 文件 | 钉住什么 |
|---|---|
| `patches/kernel-build/kernel-artifact.json` | 内核树 HEAD `86450bb7…`、提交数 136、`.config` sha `900b5a5e…`、`vmlinuz.efi`（16,134,656 B / `db5a1aa1…`）、ESP 三件套 sha |
| `patches/kernel-build/kernel-files.lock.json` | 补丁层改过的 **136 个文件**逐个 sha256 |
| `patches/kernel-build/kernel-7.2.9-gaokun3-combined.patch` | 基线 `2f6ee52…`（v7.2.9 导入）→ HEAD 的合并补丁，874,921 B |
| `patches/kernel-build/kernel-patch-manifest.txt` | 语义层：哪些上游补丁打了、哪些故意没打、为什么 |

校验：

```bash
bash build/patches/verify_kernel.sh          # 版本/git/config/补丁文本/文件锁/产物，约 3 秒
REPLAY=1 bash build/patches/verify_kernel.sh # 再检出基线打一遍合并补丁，逐字节比 136 个文件，约 1 分钟
bash build/patches/verify_all.sh             # 总闸，第 5 层就是它
```

合并补丁已经实测过：检出 `2f6ee52` → `git apply` → 136/136 文件与当前树逐字节一致。所以内核树丢了也能重建（前提是手上有 v7.2.9 的 tarball 或同基线仓库）。

**动过内核之后必须做的三件事**（顺序不能省）：

1. 重新导出合并补丁 + 文件锁（`work/make_kernel_lock.sh` 那套逻辑，改 HEAD~N 的 N），更新 `kernel-artifact.json` 的 head/count/patch sha；
2. 重新编译 `vmlinuz.efi`，**上新机验证能开机**——编译产物 sha 变了就不能直接写账本；
3. 刷进 ESP 并回读 sha，再更新 `esp.image`。

内核 build 不可能字节复现（工具链、时间戳），所以这一层验的是"源码相同 + 产物相同"，不是"能重编出一模一样的字节"。

## 十一、KernelSU（root）集成 —— ReSukiSU v4.2.0-rc3

root 走 **ReSukiSU v4.2.0-rc3**（`github.com/ReSukiSU/ReSukiSU`，pin `239e1e8871b8fcd51a6e5b3002e0ba522fdd99fb`），与同名管理器 APK（`com.resukisu.resukisu`，versionCode 35171，UAPI 4）配套。这是 vahiru 在 7.2.9 上验证过的组合。

**为什么是 rc3 而不是 v4.1.0**：v4.1.0 的 UAPI 偏低，rc3 管理器发现内核比自己旧就只提示"需要更新内核"、拒绝授权；且 v4.1.0 的 execve 挂钩里 `try_set_access_flag`（手动走页表改 PTE 访问位）在 7.2 的原子上下文里会 kernel panic。rc3 重写了挂钩，并自带 `tools/kernel_compat.mk` 按内核源码自动探测 API（不写死版本号），对主线友好。

复现步骤（接在第五节配置之后）：

```bash
# 1) 克隆 rc3 + 打兼容补丁 + 建 drivers/kernelsu 软链（脚本已 pin 239e1e88）
GAOKUN_VENDOR=vendor/gaokun-android bash vendor/gaokun-android/scripts/kernel-setup-resukisu.sh ~/kbuild/linux-7.2.9-gk3
# 2) 配置：KSU 走 tracepoint 钩子（需 FTRACE_SYSCALLS）
./scripts/config -e KSU -e KSU_TRACEPOINT_HOOK -e FTRACE_SYSCALLS -e KPROBES -e KRETPROBES
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
# 3) 注入管理器签名后编译（否则管理器不被内核信任）
KSU_EXPECTED_SIZE=0x377 \
KSU_EXPECTED_HASH=d3469712b6214462764a1d8d3e5cbe1d6819a0b629791b9f4101867821f1df64 \
CPATH=~/ssl/usr/include:~/ssl/usr/include/x86_64-linux-gnu \
LIBRARY_PATH=~/ssl/usr/lib/x86_64-linux-gnu \
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) vmlinuz.efi
```

要点：

- 7.2.9 上只需 `patches/resukisu/0002`（strncpy 兼容）；0001（text-patching.h 改名）/0003（task_stack.h）上游 rc3 已含，不用打。
- 树内挂钩 `drivers/Kconfig`（`source "drivers/kernelsu/Kconfig"`）+ `drivers/Makefile`（`obj-$(CONFIG_KSU) += kernelsu/`）与 KSU 版本无关，提交 `e36b3ae` 已含；`drivers/kernelsu` 软链由 setup 脚本建立、不入 git。
- 管理器签名 `0x377 / d3469712…` 来自 rc3 release APK 的 v2 签名块，必须经 `KSU_EXPECTED_SIZE/HASH` 编进内核。
- 验收：管理器主页显示「工作中」、内核驱动版本与管理器版本都是 `v4.2.0-rc3 (35171/4)`；shell `su -c id` 返回 `uid=0(root) context=u:r:ksu:s0`。

## 十二、boot-only 极速 OTA 与免 root 槽控制（调试通道）

换内核验证不必每次走 2 GiB 全量包。两条已打通的捷径：

**boot-only payload**（`tools/ota/make_boot_payload.py`）：只含一个 `boot` 静态分区 REPLACE 的 payload（约 28 MB）。坑：全 REPLACE 无源操作会被引擎判为 full payload，**`minor_version` 必须 0**（写 4 报 `kUnsupportedMinorPayloadVersion`）；分区名用 `boot`，引擎自动补目标槽后缀。设备端 shell 直调引擎安装（约 0.8 s）：

```bash
update_engine_client --reset_status   # 若停在 UPDATED_NEED_REBOOT 必须先复位
update_engine_client --update --follow --payload=http://<PC>:8855/payload.bin \
  --headers='FILE_HASH=…\nFILE_SIZE=…\nMETADATA_HASH=…\nMETADATA_SIZE=…\nMETADATA_SIGNATURE=…'
```

**免 root 槽控制**：设备无 `bootctl`，但 shell 可直连 boot HAL binder（SELinux permissive，HAL 不校验 uid）。方法号按字母序：

```bash
service call android.hardware.boot.IBootControl/default 1          # getActiveBootSlot
service call android.hardware.boot.IBootControl/default 9 i32 0    # setActiveBootSlot A（同步镜像 ESP 默认条目）
service call android.hardware.boot.IBootControl/default 8          # markBootSuccessful
service call android.hardware.boot.IBootControl/default 10 i32 0   # setSlotAsUnbootable A
```

迭代闭环：WSL 编内核 → Win python 换 boot 镜像 kernel 段（`work/pack_boot_a_ksu.py`）→ `make_boot_payload` → 刷 index → 设备 `reset_status`+install → binder 切槽 → reboot → 验证，一轮约 2 分钟。

**救援教训**：gk3boot 的 a/b 条目都按 misc BCAB 选槽、不看条目名；rescue 进系统会把当前槽洗白成 successful。若 boot_a 是坏内核，两条目会反复启坏内核死循环——用 binder 把活动槽切到好内核所在的 B 槽即可正常重启，不必进救援。
