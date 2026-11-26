#!/usr/bin/env python3
"""只含 boot 静态分区 REPLACE 的增量 payload（~30MB）。

用途：内核二分迭代——不碰 super，秒级安装。分区名用清单名 boot，
update_engine 自动加目标槽后缀（boot_a/boot_b）。布局与 append_boot_part.py
完全一致：header+manifest+metadata签名+数据+payload签名，双签名重算。
"""
import argparse, base64, hashlib, json, os, struct, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "proto"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import update_metadata_pb2 as um
from make_payload import sign, sign_digest, MAGIC, VERSION

BLOCK = 4096


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--name", default="boot")
    a = ap.parse_args()

    img = open(a.image, "rb").read()
    raw_len = len(img)
    if len(img) % BLOCK:
        img += b"\0" * (BLOCK - len(img) % BLOCK)
    img_hash = hashlib.sha256(img).digest()
    print(f"镜像 {raw_len} B -> 补齐 {len(img)} B")

    m = um.DeltaArchiveManifest()
    # 全 REPLACE 无源操作 ⇒ 引擎判定为 full payload，强制要求 minor 0
    # （delta_performer.cc:1330 "all full payloads should have version 0"）
    m.minor_version = 0
    pu = m.partitions.add()
    pu.partition_name = a.name
    op = pu.operations.add()
    op.type = um.InstallOperation.REPLACE
    op.data_offset = 0
    op.data_length = len(img)
    op.data_sha256_hash = img_hash
    de = op.dst_extents.add()
    de.start_block = 0
    de.num_blocks = len(img) // BLOCK
    info = pu.new_partition_info
    info.size = len(img)
    info.hash = img_hash

    m.signatures_offset = len(img)
    sig_len = len(sign(b"\0" * 64, a.key))
    m.signatures_size = sig_len
    manifest_bytes = m.SerializeToString()
    header = MAGIC + struct.pack(">QQI", VERSION, len(manifest_bytes), sig_len)
    metadata = header + manifest_bytes
    signature = sign(metadata, a.key)
    h = hashlib.sha256()
    h.update(metadata)
    h.update(img)

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "wb") as f:
        f.write(metadata)
        f.write(signature)
        f.write(img)
        f.write(sign_digest(h.digest(), a.key))

    file_size = os.path.getsize(a.out)
    fh = hashlib.sha256()
    with open(a.out, "rb") as src:
        for chunk in iter(lambda: src.read(8 << 20), b""):
            fh.update(chunk)
    props = {
        "FILE_HASH": base64.b64encode(fh.digest()).decode(),
        "FILE_SIZE": str(file_size),
        "METADATA_HASH": base64.b64encode(hashlib.sha256(metadata).digest()).decode(),
        "METADATA_SIZE": str(len(metadata)),
        "METADATA_SIGNATURE": base64.b64encode(signature).decode(),
    }
    with open(a.out + ".properties", "w", encoding="utf-8", newline="\n") as f:
        for k, v in props.items():
            f.write(f"{k}={v}\n")
    print(f"写出 {a.out}（{file_size} B）+ properties")
    print(json.dumps(props, indent=1))


if __name__ == "__main__":
    main()