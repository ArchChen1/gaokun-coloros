#!/usr/bin/env python3
"""离线自检 make_payload.py 产出的 payload：不发到设备也能确认结构和内容对。

检查项：
  1. header（魔数 / 版本 / manifest 长度 / 签名长度）与数据区偏移自洽
  2. 每个 op 的 data_offset 严格连续、data_length 与实际可读字节一致
  3. 每个 op 的 data_sha256_hash 与所读 blob 一致（压缩块按压缩后字节算）
  4. 各分区 extents 从 0 起严格升序、无空洞、覆盖分区大小
  5. 解码后按 extents 重拼分区，整体 sha256 必须等于 new_partition_info.hash

    python tools/ota/verify_payload.py --payload work/payload/payload.bin
"""
import argparse
import bz2
import hashlib
import lzma
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "proto"))
import update_metadata_pb2 as um  # noqa: E402

BLOCK = 4096


def decode(op, blob):
    t = op.type
    if t == um.InstallOperation.REPLACE:
        return blob
    if t == um.InstallOperation.REPLACE_XZ:
        return lzma.decompress(blob)
    if t == um.InstallOperation.REPLACE_BZ:
        return bz2.decompress(blob)
    raise SystemExit(f"不认识的 op 类型 {t}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--payload", required=True)
    ap.add_argument("--out-dir", default="", help="把解码后的分区写出来（可选，占空间）")
    a = ap.parse_args()

    stats = {"ops": 0, "zero": 0, "replace": 0, "xz": 0, "bz": 0,
             "data": 0, "raw": 0}
    with open(a.payload, "rb") as f:
        magic = f.read(4)
        if magic != b"CrAU":
            raise SystemExit(f"魔数不对：{magic!r}")
        version, msize, ssize = struct.unpack(">QQI", f.read(20))
        manifest_bytes = f.read(msize)
        f.read(ssize)
        data_start = 4 + 20 + msize + ssize
        m = um.DeltaArchiveManifest()
        m.ParseFromString(manifest_bytes)
        print(f"version={version} manifest={msize} B 签名={ssize} B 数据区起点={data_start} "
              f"block_size={m.block_size}")
        if m.block_size != BLOCK:
            raise SystemExit(f"block_size 异常：{m.block_size}")

        offset = 0
        for pu in m.partitions:
            name = pu.partition_name
            hpart = hashlib.sha256()
            expect_block = 0
            buf_out = open(os.path.join(a.out_dir, name + ".img"), "wb") if a.out_dir else None
            for op in pu.operations:
                stats["ops"] += 1
                ext = op.dst_extents
                if len(ext) != 1:
                    raise SystemExit(f"{name}: op 有 {len(ext)} 个 extent，本工具只处理单 extent")
                start = ext[0].start_block
                nblocks = ext[0].num_blocks
                if start != expect_block:
                    raise SystemExit(f"{name}: extent 不连续，期望 {expect_block} 实得 {start}")
                expect_block += nblocks
                if op.type == um.InstallOperation.ZERO:
                    if op.HasField("data_length") or op.HasField("data_offset"):
                        raise SystemExit(f"{name}: ZERO 带数据字段")
                    stats["zero"] += nblocks * BLOCK
                    hpart.update(b"\0" * (nblocks * BLOCK))
                    if buf_out:
                        buf_out.write(b"\0" * (nblocks * BLOCK))
                    continue
                if op.data_offset != offset:
                    raise SystemExit(f"{name}: data_offset 不连续，期望 {offset} 实得 {op.data_offset}")
                blob = f.read(op.data_length)
                if len(blob) != op.data_length:
                    raise SystemExit(f"{name}: 数据区提前结束")
                offset += op.data_length
                stats["data"] += op.data_length
                if op.HasField("data_sha256_hash") and hashlib.sha256(blob).digest() != op.data_sha256_hash:
                    raise SystemExit(f"{name}: op 数据 sha 不符")
                raw = decode(op, blob)
                stats["raw"] += len(raw)
                if len(raw) != nblocks * BLOCK:
                    raise SystemExit(f"{name}: 解码长度 {len(raw)} != {nblocks * BLOCK}")
                if op.type == um.InstallOperation.REPLACE:
                    stats["replace"] += 1
                elif op.type == um.InstallOperation.REPLACE_XZ:
                    stats["xz"] += 1
                else:
                    stats["bz"] += 1
                hpart.update(raw)
                if buf_out:
                    buf_out.write(raw)
            if buf_out:
                buf_out.close()
            size = expect_block * BLOCK
            if pu.new_partition_info.size != size:
                raise SystemExit(f"{name}: 覆盖 {size} B，但 new_partition_info.size={pu.new_partition_info.size}")
            if hpart.digest() != pu.new_partition_info.hash:
                raise SystemExit(f"{name}: 重拼 sha 不符\n  实得 {hpart.hexdigest()}\n"
                                 f"  声明 {pu.new_partition_info.hash.hex() if hasattr(pu.new_partition_info.hash,'hex') else bytes(pu.new_partition_info.hash).hex()}")
            print(f"  {name:>14}  {size/2**20:9.1f} MiB  ops={len(pu.operations):5d}  "
                  f"sha={hpart.hexdigest()[:16]}…")
        if offset != m.signatures_offset:
            raise SystemExit(f"数据区 {offset} B != signatures_offset {m.signatures_offset}")
        tail = f.read()
        print(f"payload 签名 blob {len(tail)} B（末尾）")
        total = offset + len(tail)
        file_size = os.path.getsize(a.payload)
        if total + data_start != file_size:
            raise SystemExit(f"文件尺寸不自洽：{data_start}+{total} != {file_size}")

    print(f"ops={stats['ops']}（REPLACE {stats['replace']} / XZ {stats['xz']} / BZ {stats['bz']} / ZERO {stats['zero']//BLOCK} 块）")
    print(f"数据区 {stats['data']/2**30:.2f} GiB，原始 {stats['raw']/2**30:.2f} GiB，"
          f"压缩比 {stats['data']/max(stats['raw'],1):.3f}")
    print("PAYLOAD_VERIFY_PASSED")


if __name__ == "__main__":
    main()
