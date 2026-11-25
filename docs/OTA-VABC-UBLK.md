# VABC 快照：从 dm-user 换到 ublk

AVB 卡点（见 `OTA-ENGINE-AVB-SKIP.md`）解决后，小快照包一路推进到 `VERIFYING`，
之后又踩了两层，都已定位：

## 1. `/metadata` 写满

```
Failed to write to fd 15: No space left on device
Unable to write SnapshotStatus to /metadata/ota/snapshots/my_region_b
CreateUpdateSnapshotsInternal failed: Error
```

`/metadata` 只有 25 MB，被我们自己之前排查开机留下的 `/metadata/gk3-debug`（22.7 MB 的
logcat/kmsg 转储）占满。这个目录是 0777，`shell` 可以直接清空：

```
adb shell "rm -rf /metadata/gk3-debug/*"
```

清完后 `/metadata` 从 100% 降到 11%。

## 2. 引擎想用 dm-user，但内核没有

清完空间后 COW 走**内核 dm-snapshot** 建成：

```
Mapped COW device for my_region_b at /dev/block/dm-13
```

但验证阶段去建 `dm-user` 设备：

```
Timed out waiting for snapuserd to be ready.
Could not map dm-user device for partition my_region_b
Unable to open /dev/block/mapper/my_region_b for reading.
→ kFilesystemVerifierError (47)
```

内核实际能力（`/proc/config.gz`）：

| 配置 | 值 |
|---|---|
| `CONFIG_DM_SNAPSHOT` | y |
| `CONFIG_BLK_DEV_UBLK` | y |
| `CONFIG_USERFAULTFD` | y |
| `CONFIG_DM_USER` | **没有** |

所以 dm-user 这条路在本机永远走不通，必须切到 ublk 后端。

## 3. 门控属性

引擎和 snapuserd 各自的二进制里都有对应逻辑：

- `update_engine`：`ro.virtual_ab.ublk.enabled`、`/dev/block/ublkb`、`SetupDmLinearOverUblk`、
  `snapuserd is in dm-user mode. Restarting in ublk mode.`、`Disabling UBLK backend for snapshots, requested through manifest.`
- `snapuserd`：`ro.virtual_ab.ublk.enabled`、`ublksrv_ctrl_*`、`/dev/block/ublkb`、
  `Using ublk mode based on hint file.`

设备上这两个属性原来都不存在（只有 `ro.virtual_ab.enabled=true`），所以引擎走 dm-user 分支。
把 `ro.virtual_ab.ublk.enabled=true` 写进 `system/build.prop` 即可改走 ublk。

`/dev/ublk-control`（`crw------- root root`）和 `/dev/userfaultfd` 开机自带，snapuserd 以
root 运行，权限足够。

## 4. 顺带修掉的 payload 侧误解

`cow_version >= 3` 才会带 `gz` 压缩，而**压缩快照只能用 dm-user 读**。所以打快照包一律
`COW_VER=2`（无压缩）：

```
COW_VER=2 bash work/build_snap_payload.sh
```

判断依据：`make_payload.py` 里 `if dpm.vabc_enabled and dpm.cow_version >= 3` 才设
`vabc_compression_param="gz"` 和 `compression_factor=4096`。

## 5. 真凶：`snapuserd` 缺 `ro.virtual_ab.userspace.snapshots.enabled`

前几轮一直在怀疑 init 触发没生效（试过 `on property:ro.virtual_ab.ublk.enabled=true`、
`on boot`、`on property:sys.boot_completed=1`、`-ublk` 参数、kmsg 标记、`gk3diag` 探针），
方向全错。真相是 init **确实执行了 `start snapuserd`**，但守护进程自己拒绝启动。

决定性操作（`ctl.start` 从 `shell` 就能写，不需要 root）：

```sh
adb shell setprop ro.virtual_ab.userspace.snapshots.enabled true   # ro. 未设时可首次写入
adb shell setprop ctl.start snapuserd
```

kmsg 直接给出原因：

```
init: starting service 'snapuserd'...
snapuserd: Userspace snapshots not enabled. No support for legacy snapshots
snapuserd: Snapuserd daemon failed to start
init: Service 'snapuserd' (pid ...) exited with status 1 oneshot service took 0.034s
```

补上属性后立刻 `running`，并打印 `Mode explicitly set via command-line flag: ublk` /
`Supporting UBLK snapshots` / `Now listening on snapuserd socket`。

结论：

- `ro.virtual_ab.ublk.enabled` 只决定**后端**（ublk vs dm-user），不决定是否允许
  userspace snapshot；
- `ro.virtual_ab.userspace.snapshots.enabled=true` 才是 `snapuserd` 的**总开关**，
  这份 ColorOS 构建从未设置过；
- 两个属性都必须固化进 `build.prop`：

```
ro.virtual_ab.ublk.enabled=true
ro.virtual_ab.userspace.snapshots.enabled=true
```

## 6. 调试手段备忘（都不需要 root 或刷镜像）

- `adb shell setprop ctl.start <svc>`：**可直接让 init 启动任意已注册服务**（无需 `adb root`）。
- `adb shell setprop debug.* 1`：可写，配合 `on property:` 触发 init 动作。
- `snapuserd` 的日志走 **kmsg** 而非 logcat；`dmesg` 环形缓冲约保留 40–50 秒，
  开机期日志会被冲掉，所以用 `ctl.start` 在运行时复现最省事。
- 手动在 shell 里裸跑 `snapuserd` 永远 `rc=1` 且无输出：拿不到 init 提供的
  `ANDROID_SOCKET_snapuserd`（`socket snapuserd stream 0660 system system` 由 init 创建）。

## 7. 闭环验收记录（2026-11-26）

链路：`region_snap.bin`（`COW_VER=2`，源 `v49/src/my_region_a.img`，7,238,361 B）
→ `update_engine_client --update --follow`

```
UPDATE_STATUS_VERIFYING (4) ... 1
UPDATE_STATUS_FINALIZING (5) 0
onPayloadApplicationComplete(ErrorCode::kSuccess (0))
UPDATE_STATUS_UPDATED_NEED_REBOOT (6)
```

随后 `update_engine_client --merge` 返回 `ErrorCode::kSuccess (0)`（2 ms，无待合并项），
`/metadata/ota/snapshots` 为空目录，`/metadata/ota/new_partition.csv` 记录：

```
my_region,7237632,V4P/g9NkC2SSI6o3cYcVPrOb2+sPLfqw3D++UONvfwI=
```

base64 解码 = `5783ff83d3640b649223aa377187153eb39bdbeb0f2dfab0dc3fbe50e36f7f02`。

盘上实读（root runner `gk3run` 执行 `dd`）：super 内 `my_region_a` extent
sector `19638272`、14136 扇区：

```
5783ff83d3640b649223aa377187153eb39bdbeb0f2dfab0dc3fbe50e36f7f02  /data/local/tmp/mr_a.img
```

**三者一致** → 安装、内联合并、物理落盘全部成立。注意：VABC 同槽更新是**安装结束时内联合并**，
不是重启后合并，所以 `UPDATED_NEED_REBOOT` 之后并不需要真的切槽。

另：这份 super 只有 `_a` 分区（lpdump 无任何 `_b`），B 槽镜像副本在 `coloros-build/*/zb/`
是离线产物，不在盘上。

## 8. `gk3run`（调试后门，发布前必须删）

`system/etc/init/snapuserd.rc` 里的按需 root runner：

```
service gk3run /system/bin/sh /data/local/tmp/gk3run.sh
    user root
    group root system
    oneshot
    disabled
```

用法：`adb push` 脚本到 `/data/local/tmp/gk3run.sh`（注意转掉 CRLF）→
`adb shell setprop ctl.start gk3run` → 结果由脚本自己写到 `/data/local/tmp/`。
不参与开机流程，不设 `seclabel`（落在 `u:r:oppo_shell:s0`，本机 Permissive）。

**发布清单**：删 `gk3run`、删 `gk3clean` 对 `/metadata` 的清理动作、删本文件第 6 节的
调试属性写法，并把 `ro.virtual_ab.userspace.snapshots.enabled` 保留。

## 9. 下一层的真实约束：`/metadata` 只有 25 MB

VABC 的 COW 全部落在 `/metadata/ota/snapshots`。本次 7.2 MB 分区整块替换没有压力，
但**整块替换 system（1.1 GB）时 COW 会远超 25 MB**，单份 super + 快照方案在容量上会卡住。
可选方向：

1. 只发**增量快照包**（改动块小，COW 落在 25 MB 内）——与本项目实际改动量匹配；
2. 扩容 `/metadata`（GPT 改分区，后续分区要顺移，风险高，需专门评估）；
3. 退回双槽全量覆盖（放弃单份 super 目标）。
