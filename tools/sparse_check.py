#!/usr/bin/env python3
"""校验 super.img 的 sparse 头：魔数、块大小、展开后的总字节数。

用法：
    sparse_check.py <super.img> [期望展开字节数]

Android sparse 头（28 字节）：
    0  u32 magic 0xED26FF3A   4  u16 major   6  u16 minor   8  u16 file_hdr_sz
   10  u16 chunk_hdr_sz      12 u32 blk_sz  16 u32 total_blk  20 u32 total_chunks
   24  u32 image_checksum
"""
import os
import struct
import sys

MAGIC = 0xED26FF3A
SUPER_BYTES = 21474836480  # 20 GiB


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[3], file=sys.stderr)
        return 2
    path = os.path.realpath(argv[1])
    want = int(argv[2]) if len(argv) > 2 else SUPER_BYTES
    with open(path, "rb") as f:
        hdr = f.read(28)
    if len(hdr) < 28:
        print(f"FAIL {path}: 连 sparse 头都读不到")
        return 1
    magic, major, minor, fhs, chs, blk, total_blk, total_chunks = struct.unpack("<IHHHHIII", hdr[:24])
    if magic != MAGIC:
        print(f"FAIL {path}: magic 0x{magic:08X}，不是 sparse（普通 raw 镜像？）")
        return 1
    size = os.path.getsize(path)
    expanded = total_blk * blk
    print(f"  sparse v{major}.{minor} blk={blk} 分块={total_chunks} 展开={expanded} 字节 文件={size} 字节")
    if expanded != want:
        print(f"FAIL 展开后 {expanded} != 期望 {want}")
        return 1
    print(f"  SPARSE_OK {want} 字节（{want // (1 << 30)} GiB）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
