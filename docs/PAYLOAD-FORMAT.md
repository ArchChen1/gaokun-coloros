# payload 格式（`update_engine` 官方路径）

2026-11-24 打通：自写生成器 `tools/ota/make_payload.py` 出的 2 分区测试包（`my_manifest` 716,800 B、
`my_region` 7,237,632 B）在真机上走完 `DOWNLOADING → VERIFYING → FINALIZING → kSuccess (0)`，
回读 B 槽两个扇区区间（39294976 起 1400 扇区、39297024 起 14136 扇区）的 sha256 与源镜像一致，
确认数据真的写进了 `super` 的目标槽逻辑分区。

## 文件布局

```
[header 24B][manifest][metadata 签名][分区数据][payload 签名 blob]
```

- header = `CrAU` + 大端 u64 版本(2) + u64 manifest 长度 + u32 metadata 签名长度
- `manifest.signatures_offset` 是**相对数据区起点**的偏移（= 数据区总长），blob 紧跟数据之后
- metadata 签名覆盖 `payload[0, metadata_size)`，即 header + manifest
- payload 签名覆盖 `sha256(manifest + 数据)`（跳过 metadata 签名本身）

## 踩过的坑（按报错顺序）

| 报错 | 真正的原因 |
| --- | --- |
| `kDownloadInvalidMetadataSize (32)` | `METADATA_SIZE` 只含 header+manifest，不含签名；签名走 `METADATA_SIGNATURE` |
| 同上 | v2 的 metadata 签名必须是**序列化后的 `Signatures` protobuf**，不是裸 RSA 字节 |
| `kDownloadMetadataSignatureVerificationError (25)` | `otacerts.zip` 条目名必须以 `x509.pem` 结尾（源码用 `"x509.pem"` 后缀过滤）；叫 `ota_cert.pem` 一个都取不到 |
| 同上 | 签名对象要含 header，只签 manifest 会不匹配 |
| `kDownloadNewPartitionInfoError (13)` | 每个分区必须有 `new_partition_info`（size + 目标 sha256） |
| `kInstallDeviceOpenError (7)` | 目标槽是动态分区，manifest 缺 `dynamic_partition_metadata`；组名给不带后缀的 `gaokun3_dynamic_partitions` |
| 同上 | `super` 元数据必须是 legacy A/B：slot 0 只放 `_a`、slot 1 只放 `_b`，否则报 `duplication partition` |
| `kPayloadHashMismatchError (10)` | properties 里的 `FILE_HASH`/`METADATA_HASH` 是 **base64**，写成十六进制会被解成 48 字节垃圾 |
| `kDownloadOperationHashMissingError (38)` | 每个 operation 的 `data_sha256_hash` 必须给 |
| `kDownloadPayloadPubKeyVerificationError (18)` | payload 签名的哈希范围不对；另外 `cryptography` 默认会再哈希一次，必须用 `Prehashed(SHA256)` 签摘要 |
| `kSignedDeltaPayloadExpectedError (17)` | 缺 payload 签名 blob，`signatures_offset/_size` 没填 |

## super 元数据：两个槽，各管一份

`lpmake --virtual-ab` 会把 26 个分区全塞进同一个 metadata slot，update_engine 从源槽读表后再加
`my_manifest_b` 就撞名。要的是 legacy A/B 形态，`tools/ota/mk_slot_meta.py` 的做法：

1. 只用 `_a` 分区跑一次 lpmake（顺序、尺寸与真实布局一致，extents 天然对齐）；
2. 用 `pad` 分区把起点推到 19660800 扇区，再放 `_b` 分区跑第二次；
3. 按主/备份槽偏移（12288 / 77824 / 143360 / 208896）把两份 1 MiB 元数据头拼起来，只写 `super` 前 1 MiB。

备份与恢复：

```
dd if=/dev/block/by-name/super of=/data/local/tmp/super_meta_backup.bin bs=4096 count=256
dd if=/data/local/tmp/meta_merged.bin of=/dev/block/by-name/super bs=4096 count=256
lpdump -s 0 /dev/block/by-name/super   # 全是 _a
lpdump -s 1 /dev/block/by-name/super   # pad + 全是 _b
```

## 已知遗留

- apply 成功后 `update_engine` 会把目标槽 metadata 改写成源槽的表（Slot 1 变成 `_a` 分区），目前靠重写
  `meta_merged.bin` 复原；全量包阶段要确认它是否把 `_b` 条目写回，否则切 B 会挂错分区。
- `/metadata/ota/state` 写入偶发 `No space left on device`，要查 `/metadata` 余量。
- 尚未跑 13 分区全量包；`otacerts.zip` 仍需打进 `my_engineering`（现在是 bind mount，重启即失效）。
