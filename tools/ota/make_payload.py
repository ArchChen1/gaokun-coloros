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
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
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
SNAPSHOT = False  # --snapshot 打开时走 VABC 快照


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
        h = hashlib.sha256()
        with open(path, "rb") as src:
            for chunk in iter(lambda: src.read(8 << 20), b""):
                h.update(chunk)
        digest = h.digest()
        op.data_sha256_hash = digest
        info = pu.new_partition_info
        info.size = size
        info.hash = digest
        if SNAPSHOT:
            # VABC 要按分区预留 COW 空间；全量 REPLACE 等于整份都要抄一遍
            pu.estimate_cow_size = size + (1 << 20)

    # 声明目标分区是动态分区（super 里的逻辑分区），否则 update_engine 会去
    # /dev/block/by-name/<name>_b 找块设备，而动态分区根本没有节点。
    # snapshot_enabled 决定走 VABC 快照（写 COW、成功后合并、失败可回滚）还是
    # 直接写当前槽（in-place，无回滚）。由 --snapshot 控制。
    dpm = m.dynamic_partition_metadata
    dpm.snapshot_enabled = SNAPSHOT
    dpm.vabc_enabled = SNAPSHOT and os.environ.get("VABC", "1") == "1"
    if SNAPSHOT:
        dpm.cow_version = int(os.environ.get("COW_VER", "2"))  # 设备允许 1..3，缺省 0 会直接被判越界
        if dpm.vabc_enabled and dpm.cow_version >= 3:
            dpm.vabc_compression_param = "gz"
            dpm.compression_factor = 4096  # 0 会被 cow writer 判为非法
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
    ap.add_argument("--parts", default="", help="分区镜像目录（调试用；正式出包请用 --manifest）")
    ap.add_argument("--manifest", default="",
                    help="manifest.json 账本：按其中的 path+bytes+sha256 取 13 个分区，任一不符即退出")
    ap.add_argument("--key", required=True, help="RSA 私钥 PEM（对应 otacerts.zip 里的证书）")
    ap.add_argument("--out", required=True)
    ap.add_argument("--version", default="")
    ap.add_argument("--only", default="", help="只打包这些分区（调试用，逗号分隔）")
    ap.add_argument("--snapshot", action="store_true", help="走 VABC 快照（默认直接写当前槽）")
    ap.add_argument("--group", default="",
                    help="dynamic_partition_metadata 里的组名；VABC 必须与设备 lpdump 里的组名逐字相同（带槽后缀）")
    a = ap.parse_args()
    global SNAPSHOT, DYNAMIC_GROUP
    SNAPSHOT = a.snapshot
    DYNAMIC_GROUP = a.group or DYNAMIC_GROUP

    wanted = {s.strip() for s in a.only.split(",") if s.strip()} if a.only else None
    entries = []
    if a.manifest:
        # 唯一正式来源：账本。任何 sha / 大小不符都直接停 —— 这就是「补丁不能悄悄丢」的那道闸。
        import parts_manifest as pm
        man = json.load(open(a.manifest, encoding="utf-8"))
        pm_parts = man.get("parts", {})
        for name, fname in PARTS:
            if wanted and name not in wanted:
                continue
            p = pm_parts.get(name)
            if not p:
                raise SystemExit(f"账本里没有 {name}（{a.manifest}）")
            path = p["path"]
            if not os.path.isfile(path):
                raise SystemExit(f"账本记录的产物不存在：{name} -> {path}")
            size = os.path.getsize(path)
            if p.get("bytes") and size != p["bytes"]:
                raise SystemExit(f"{name} 大小与账本不符：{size} != {p['bytes']}（{path}）")
            got = pm.sha256(path)
            if got != p.get("sha256"):
                raise SystemExit(f"{name} sha 与账本不符：{got[:16]}… != {str(p.get('sha256'))[:16]}…"
                                 f"（补丁丢了？{path}）")
            entries.append((name, path, size))
        print(f"来源=账本 {a.manifest}（generated={man.get('generated', '?')}，{len(entries)} 个分区已核对）")
    elif a.parts:
        print("!! 警告：--parts 目录模式绕过账本校验，只用于调试；正式出包请用 --manifest")
        for name, fname in PARTS:
            if wanted and name not in wanted:
                continue
            path = os.path.join(a.parts, fname)
            if not os.path.isfile(path):
                raise SystemExit(f"缺镜像: {path}")
            entries.append((name, path, os.path.getsize(path)))
    else:
        raise SystemExit("必须给 --manifest（正式）或 --parts（调试）")

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
    fh = hashlib.sha256()
    with open(a.out, "rb") as src:
        for chunk in iter(lambda: src.read(8 << 20), b""):
            fh.update(chunk)
    file_hash = fh.digest()
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
    # newline="\n" 必须显式给：Windows 上默认会写 CRLF，设备侧 k=v 解析会把 \r 带进
    # hash 值里，直接 kPayloadHashMismatchError (10)
    with open(props_path, "w", encoding="utf-8", newline="\n") as f:
        for k, v in props.items():
            f.write(f"{k}={v}\n")

    print(f"分区 {len(entries)} 个，metadata {len(metadata)} B，payload {file_size/2**30:.2f} GiB")
    print(f"manifest sha256 {meta_hash.hex()[:16]}…  签名 {len(signature)} B")
    print(f"写出 {a.out}")
    print(f"写出 {props_path}")
    print(json.dumps(props, indent=1))


if __name__ == "__main__":
    main()




