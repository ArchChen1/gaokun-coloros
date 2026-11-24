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
from cryptography.hazmat.primitives.asymmetric import padding, utils

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

DYNAMIC_GROUP = "gaokun3_dynamic_partitions"


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
        # 全量 REPLACE 的 data 就是整份镜像，哈希必须给（hash_checks_mandatory）
        digest = hashlib.sha256(open(path, "rb").read()).digest()
        op.data_sha256_hash = digest
        info = pu.new_partition_info
        info.size = size
        info.hash = digest

    # 声明目标槽的分区是动态分区（super 里的逻辑分区），否则 update_engine 会
    # 去 /dev/block/by-name/<name>_b 找块设备，而动态分区根本没有节点。
    # snapshot/vabc 都关掉：不启用虚拟 A/B 快照，直接写目标槽那一份。
    dpm = m.dynamic_partition_metadata
    dpm.snapshot_enabled = False
    dpm.vabc_enabled = False
    group = dpm.groups.add()
    group.name = DYNAMIC_GROUP
    group.size = sum(size for _, _, size in parts)
    for name, _, _ in parts:
        group.partition_names.append(name)
    return m, data_offset


def _wrap(raw):
    # 主版本 >= 2 的签名都是序列化后的 Signatures protobuf，不是裸字节
    msg = um.Signatures()
    sig = msg.signatures.add()
    sig.data = raw
    return msg.SerializeToString()


def sign(data, key_path):
    with open(key_path, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    return _wrap(key.sign(data, padding.PKCS1v15(), hashes.SHA256()))


def sign_digest(digest, key_path):
    """对已经算好的 sha256 摘要签名。

    cryptography 的 PKCS1v15 默认会把输入再哈希一次，这里必须用 Prehashed，
    否则签进去的是 sha256(sha256(...))，设备端比对必然不通过。
    """
    with open(key_path, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    return _wrap(key.sign(digest, padding.PKCS1v15(), utils.Prehashed(hashes.SHA256())))


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

    # 三段式签名（AOSP 全量包的标准形态）：
    #   [header][manifest][metadata 签名][分区数据][payload 签名 blob]
    # blob 在文件末尾；signatures_offset 指向它，签名覆盖它之前的全部字节；
    # metadata 签名只覆盖 header+manifest。两个签名都是 RSA-2048，序列化后的
    # Signatures protobuf 长度固定，迭代两轮即可对齐。
    # signatures_offset 是相对"数据区起点"的偏移，不是文件绝对偏移，
    # 即等于数据区总长度（blob 紧跟在数据后面）。
    manifest_bytes = manifest.SerializeToString()
    sig_len = len(sign(b"\0" * 64, a.key))
    for _ in range(4):
        manifest.signatures_offset = data_size
        manifest.signatures_size = sig_len
        new_bytes = manifest.SerializeToString()
        if len(new_bytes) == len(manifest_bytes):
            break
        manifest_bytes = new_bytes

    header = MAGIC + struct.pack(">QQI", VERSION, len(manifest_bytes), sig_len)
    metadata = header + manifest_bytes
    signature = sign(metadata, a.key)

    prefix_len = len(metadata) + len(signature)
    payload_sig = sign_digest(hashlib.sha256(b"pad").digest(), a.key)  # 占位，仅取长度
    assert len(payload_sig) == sig_len

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    h = hashlib.sha256()
    with open(a.out, "wb") as f:
        f.write(metadata)
        f.write(signature)
        # AOSP 的 payload 签名哈希跳过 metadata 签名本身：hash = sha256(manifest + 数据)
        h.update(metadata)
        for name, path, size in entries:
            with open(path, "rb") as src:
                left = size
                while left:
                    buf = src.read(min(8 << 20, left))
                    if not buf:
                        raise SystemExit(f"{name} 读取提前结束")
                    f.write(buf)
                    h.update(buf)
                    left -= len(buf)
        f.write(sign_digest(h.digest(), a.key))

    file_size = os.path.getsize(a.out)
    file_hash = hashlib.sha256(open(a.out, "rb").read()).digest()
    meta_hash = hashlib.sha256(metadata).digest()

    # AOSP 的 payload_properties.txt 里哈希是 base64（客户端直接 base64 解码成
    # 字节去比对），写成十六进制会被解成 48 字节垃圾，导致 kPayloadHashMismatch。
    props = {
        "FILE_HASH": base64.b64encode(file_hash).decode(),
        "FILE_SIZE": str(file_size),
        "METADATA_HASH": base64.b64encode(meta_hash).decode(),
        "METADATA_SIZE": str(len(metadata)),
        "METADATA_SIGNATURE": base64.b64encode(signature).decode(),
    }
    props_path = a.out + ".properties"
    with open(props_path, "w", encoding="utf-8") as f:
        for k, v in props.items():
            f.write(f"{k}={v}\n")

    print(f"分区 {len(entries)} 个，metadata {len(metadata)} B，payload {file_size/2**30:.2f} GiB")
    print(f"manifest sha256 {meta_hash.hex()[:16]}…  签名 {len(signature)} B")
    print(f"写出 {a.out}")
    print(f"写出 {props_path}")
    print(json.dumps(props, indent=1))


if __name__ == "__main__":
    main()



