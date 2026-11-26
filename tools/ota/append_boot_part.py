#!/usr/bin/env python3
"""给已生成的增量 payload 追加 boot_a 静态分区 REPLACE 操作。

背景：设备无 root，esp/boot 块设备 shell 读写全被拒；但 update_engine 以 root 跑，
且 gk3otad root 服务是既定写入通道。boot_a 不在 ab_ota_partitions（只有 boot），
先试「非清单静态分区」引擎是否接受——被拒也无害（解析阶段失败，不写盘）。

做法：读现有 payload.bin（header+manifest+metadata签名+数据+payload签名），
在 manifest 末尾 append 一个 PartitionUpdate(boot_a)，把新 boot 镜像数据追加到
数据区末尾（signatures blob 之前），重算两个签名与 properties。
"""
import argparse, base64, hashlib, json, os, struct, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "proto"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import update_metadata_pb2 as um
from make_payload import sign, sign_digest, MAGIC, VERSION

BLOCK = 4096


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--payload", required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--name", default="boot")
    ap.add_argument("--key", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    raw = open(a.payload, "rb").read()
    assert raw[:4] == MAGIC
    ver, mlen, siglen = struct.unpack_from(">QQI", raw, 4)
    assert ver == VERSION
    meta_end = 24 + mlen
    metadata = raw[:meta_end]
    m = um.DeltaArchiveManifest()
    m.ParseFromString(raw[24:meta_end])
    print(f"原 payload: minor={m.minor_version} 分区={len(m.partitions)} "
          f"sig_off={m.signatures_offset} sig_size={m.signatures_size}")
    names = [p.partition_name for p in m.partitions]
    assert a.name not in names, f"{a.name} 已在 payload 里"
    data_start = meta_end + siglen
    data_size = m.signatures_offset
    old_data = raw[data_start:data_start + data_size]
    # 校验原 payload 签名哈希（sha256(metadata+data)，跳过 metadata 签名本身）
    h0 = hashlib.sha256()
    h0.update(metadata); h0.update(old_data)
    print(f"原数据区 {data_size} B，重算哈希 {h0.hexdigest()[:16]}…")

    img = open(a.image, "rb").read()
    raw_len = len(img)
    # boot v2 按 2048 页对齐，boot 分区 64 MiB 尾部是零；补零到 4096 不改变任何有效内容
    if len(img) % BLOCK:
        img += b"\0" * (BLOCK - len(img) % BLOCK)
    print(f"镜像 {raw_len} B -> 补齐 {len(img)} B（尾部零填充）")
    img_hash = hashlib.sha256(img).digest()

    pu = m.partitions.add()
    pu.partition_name = a.name
    op = pu.operations.add()
    op.type = um.InstallOperation.REPLACE
    op.data_offset = data_size          # 追加在数据区末尾
    op.data_length = len(img)
    op.data_sha256_hash = img_hash
    de = op.dst_extents.add()
    de.start_block = 0
    de.num_blocks = len(img) // BLOCK
    info = pu.new_partition_info
    info.size = len(img)
    info.hash = img_hash
    # 静态分区不进 dynamic_partition_metadata（boot_a 是 GPT 物理分区）

    new_data_size = data_size + len(img)
    m.signatures_offset = new_data_size
    sig_len = len(sign(b"\0" * 64, a.key))
    m.signatures_size = sig_len
    manifest_bytes = m.SerializeToString()
    header = MAGIC + struct.pack(">QQI", VERSION, len(manifest_bytes), sig_len)
    metadata = header + manifest_bytes
    signature = sign(metadata, a.key)

    h = hashlib.sha256()
    h.update(metadata)
    h.update(old_data)
    h.update(img)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "wb") as f:
        f.write(metadata)
        f.write(signature)
        f.write(old_data)
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
    print(f"追加 {a.name} {len(img)} B sha={img_hash.hex()[:16]}…")
    print(f"写出 {a.out}（{file_size} B）+ properties")
    print(json.dumps(props, indent=1))


if __name__ == "__main__":
    main()