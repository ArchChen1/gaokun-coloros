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

## 5. 当前状态

- `system.erofs`（含 3 字节 AVB-skip 补丁 + ublk 属性）：1,137,397,760 B，
  sha256 `db11502bfe634a3164d8334324bfbf0ceabc60c5f7d8e9a92af36088f4f04c53`
- 待验：写回 `system_a` → 重启 → 重跑 `region_snap.bin`，看能否越过
  `kFilesystemVerifierError (47)`，并继续到安装完成 + `--oplus_switch_slot` 重启合并。
