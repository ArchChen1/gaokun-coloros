#!/usr/bin/env python3
"""从一目录的分区镜像生成在线更新清单 index.json（服务端要签名的对象）。

用法：
    python tools/ota/make_release.py --parts <目录> --version 17.0.2.100 \
        --channel stable --out D:/gaokun-coloros-release/ota/index.json \
        --base-url http://192.168.1.152:8001/ota/

清单结构（App 端 ReleaseSource 按这个解析）：
{
  "format": 1,
  "version": "17.0.2.100",
  "channel": "stable",
  "build_date": "2026-11-24T10:00:00+08:00",
  "total_size": 10064841728,
  "base_url": "...",       # 相对路径拼在这里
  "parts": [{"name": "system", "file": "system.img", "size": n, "sha256": "..."}],
  "signature": null        # 预留：ed25519 对除 signature 外的规范化 JSON 签名
}

只做 sha256 + 清单，不做签名（签名在 S3 定密钥后接）。
"""
import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone, timedelta

PARTS = [
    "system", "system_ext", "product", "vendor", "odm",
    "my_product", "my_stock", "my_manifest", "my_region",
    "my_engineering", "my_heytap", "my_carrier", "my_bigball",
]


def sha256_of(path, chunk=8 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def find_image(parts_dir, name):
    for cand in (f"{name}.img", f"{name}.erofs", f"{name}_a.img", f"{name}.raw"):
        p = os.path.join(parts_dir, cand)
        if os.path.isfile(p):
            return p, cand
    return None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--parts", required=True, help="含 13 个分区镜像的目录")
    ap.add_argument("--version", required=True)
    ap.add_argument("--channel", default="stable")
    ap.add_argument("--out", required=True)
    ap.add_argument("--base-url", default="")
    ap.add_argument("--note", default="")
    a = ap.parse_args()

    entries, missing, total = [], [], 0
    for name in PARTS:
        path, fname = find_image(a.parts, name)
        if not path:
            missing.append(name)
            continue
        size = os.path.getsize(path)
        total += size
        print(f"  {name:<15} {size/2**20:9.1f} MiB  {fname}", flush=True)
        entries.append({
            "name": name,
            "file": fname,
            "size": size,
            "sha256": sha256_of(path),
        })

    if missing:
        print("缺镜像: " + ", ".join(missing), file=sys.stderr)
        return 1

    doc = {
        "format": 1,
        "version": a.version,
        "channel": a.channel,
        "build_date": datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds"),
        "total_size": total,
        "base_url": a.base_url,
        "note": a.note,
        "parts": entries,
        "signature": None,
    }
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"\n写出 {a.out}  ({total/2**30:.2f} GiB, {len(entries)} 分区)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
