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

## 6. 待办（恢复这项工作时）

- 跑一次 `verify-hw-codec2.sh`，取第 3、4、5 步的真实结果，再决定方向。
- 若确定是 userspace 侧，候选是回到上游那套打满补丁的 `external/v4l2_codec2` 构建（修补 3/5/7 + `patches/android/v4l2-codec2/0001..0006`），而不是继续在 vendor 里缝。
- 相机录像依赖硬件编码器，本项不解决，录像功能就不完整；相机"官方 App 打不开"是另一个问题（provider 只枚举到 1 个后摄，官方 App 取前摄 characteristics 拿到 null 触发 NPE，第三方相机可用）。
