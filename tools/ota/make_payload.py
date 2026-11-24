#!/usr/bin/env python3
"""生成 AOSP/update_engine 能直接吃的全量 A/B payload。

格式（见 update_engine/payload_generator/payload_file.cc）：
    "CrAU"(4) | version(8, BE) | manifest_size(8, BE) | metadata_sig_size(4, BE)
    | manifest(protobuf) | manifest 签名(PKCS#1 v1.5 / SHA-256) | 数据块...

全量包用 REPLACE（不压缩）操作，每个操作覆盖一个分区的全部块，
所以不需要块哈希表；签名只覆盖 manifest。

    python tools/ota/make_payload.py --parts E:/gk3-ota-lan \
        --version 17.0.1.300 --key .secrets/payload/ota_key.pem \
        --out work/payload/payload.bin
"""
import argparse
import base64
import hashlib
import json
import os
import struct
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "proto"))
import update_metadata_pb2 as um  # noqa: E402

BLOCK = 4096
MAGIC = b"CrAU"
VERSION = 2
PARTS = [
    ("system", "system.erofs"), ("system_ext", "system_ext.img"),
    ("product", "product.img"), ("vendor", "vendor.img"),
    ("odm", "odm.erofs"), ("my_product", "my_product.erofs"),
    ("my_stock", "my_stock.erofs"), ("my_manifest", "my_manifest.img"),
    ("my_region", "my_region.img"), ("my_engineering", "my_engineering.img"),
    ("my_heytap", "my_heytap.img"), ("my_carrier", "my_carrier.img"),
    ("my_bigball", "my_bigball.img"),
]


def build_manifest(parts, block_size=BLOCK):
    """parts: [(name, path, bytes)]，按顺序生成 install_operations。"""
    m = um.DeltaArchiveManifest()
    m.block_size = block_size
    m.minor_version = 0
    data_offset = 0
    for name, path, size in parts:
        if size % block_size:
            raise SystemExit(f"{name} 大小不是 {block_size} 的整数倍: {size}")
        pu = m.partitions.add()
        pu.partition_name = name
        op = pu.operations.add()
        op.type = um.InstallOperation.REPLACE
        ext = op.dst_extents.add()
        ext.start_block = 0          # 分区内相对块号
        ext.num_blocks = size // block_size
        op.data_offset = data_offset
        op.data_length = size
        data_offset += size
        # data_sha256_hash 留空：全量包不逐块校验
        # 新版 update_engine 强制要求 new_partition_info（大小 + 目标哈希）
        info = pu.new_partition_info
        info.size = size
        info.hash = hashlib.sha256(open(path, "rb").read()).digest()
    return m, data_offset


def sign(manifest_bytes, key_path):
    with open(key_path, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    raw = key.sign(manifest_bytes, padding.PKCS1v15(), hashes.SHA256())
    # 主版本 >= 2 的 metadata 签名是序列化后的 Signatures protobuf，不是裸字节
    msg = um.Signatures()
    sig = msg.signatures.add()
    sig.data = raw
    return msg.SerializeToString()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--parts", required=True, help="分区镜像目录")
    ap.add_argument("--key", required=True, help="RSA 私钥 PEM（对应 otacerts.zip 里的证书）")
    ap.add_argument("--out", required=True)
    ap.add_argument("--version", default="")
    ap.add_argument("--only", default="", help="只打包这些分区（调试用，逗号分隔）")
    a = ap.parse_args()

    wanted = {s.strip() for s in a.only.split(",") if s.strip()} if a.only else None
    entries = []
    for name, fname in PARTS:
        if wanted and name not in wanted:
            continue
        path = os.path.join(a.parts, fname)
        if not os.path.isfile(path):
            raise SystemExit(f"缺镜像: {path}")
        entries.append((name, path, os.path.getsize(path)))

    manifest, data_size = build_manifest(entries)
    manifest_bytes = manifest.SerializeToString()

    # 签名对象是 payload[0, metadata_size)，即 header + manifest，所以要先把
    # 头部拼好再签；签名长度本身与签名的内容无关，两轮即可收敛。
    sig_len = len(sign(manifest_bytes, a.key))
    signature = b""
    for _ in range(3):
        header = MAGIC + struct.pack(">QQI", VERSION, len(manifest_bytes), sig_len)
        metadata = header + manifest_bytes
        signature = sign(metadata, a.key)
        if len(signature) == sig_len:
            break
        sig_len = len(signature)
    # METADATA_SIZE/HASH 只覆盖 header+manifest，签名单独用 METADATA_SIGNATURE 传
    blob = metadata + signature

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "wb") as f:
        f.write(blob)
        for name, path, size in entries:
            with open(path, "rb") as src:
                left = size
                while left:
                    buf = src.read(min(8 << 20, left))
                    if not buf:
                        raise SystemExit(f"{name} 读取提前结束")
                    f.write(buf)
                    left -= len(buf)

    file_size = os.path.getsize(a.out)
    file_hash = hashlib.sha256(open(a.out, "rb").read()).hexdigest()

    props = {
        "FILE_HASH": file_hash,
        "FILE_SIZE": str(file_size),
        "METADATA_HASH": hashlib.sha256(metadata).hexdigest(),
        "METADATA_SIZE": str(len(metadata)),
        "METADATA_SIGNATURE": base64.b64encode(signature).decode(),
    }
    props_path = a.out + ".properties"
    with open(props_path, "w", encoding="utf-8") as f:
        for k, v in props.items():
            f.write(f"{k}={v}\n")

    print(f"分区 {len(entries)} 个，metadata {len(metadata)} B，payload {file_size/2**30:.2f} GiB")
    print(f"manifest sha256 {props['METADATA_HASH'][:16]}…  签名 {len(signature)} B")
    print(f"写出 {a.out}")
    print(f"写出 {props_path}")
    print(json.dumps(props, indent=1))


if __name__ == "__main__":
    main()



