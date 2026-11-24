#!/usr/bin/env python3
"""把一次 OTA 发版上传到 Cloudflare R2（S3 兼容 API），并按保留策略裁剪旧版本。

凭据从 <repo>/.secrets/r2.env 读（已 gitignore），可用环境变量覆盖同名键：
    R2_ENDPOINT  R2_ACCESS_KEY_ID  R2_SECRET_ACCESS_KEY  R2_BUCKET  R2_PUBLIC_BASE

布局：
    gk3-ota/stable/index.json                 # 客户端唯一入口，永远指向最新
    gk3-ota/stable/<version>/index.json
    gk3-ota/stable/<version>/<part>.img

用法：
    # 只发清单（先验证链路，不传镜像）
    python tools/ota/r2_publish.py --parts <dir> --version 17.0.2.100 --index-only

    # 真发版：镜像 + 清单，保留最近 2 个版本
    python tools/ota/r2_publish.py --parts <dir> --version 17.0.2.100 --keep 2
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone, timedelta

import boto3
from boto3.s3.transfer import TransferConfig
from botocore.exceptions import ClientError

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_release import PARTS, find_image, sha256_of  # noqa: E402

ENV_FILE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), ".secrets", "r2.env")


def load_env():
    env = {}
    if os.path.isfile(ENV_FILE):
        for line in open(ENV_FILE, encoding="utf-8-sig"):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    for k in ("R2_ENDPOINT", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET", "R2_PUBLIC_BASE"):
        if os.environ.get(k):
            env[k] = os.environ[k]
    return env


def client(env):
    return boto3.client(
        "s3",
        endpoint_url=env["R2_ENDPOINT"],
        aws_access_key_id=env["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=env["R2_SECRET_ACCESS_KEY"],
        region_name="auto",
    )


def build_index(parts_dir, version, channel, base_url, note):
    entries, missing, total = [], [], 0
    for name in PARTS:
        path, fname = find_image(parts_dir, name)
        if not path:
            missing.append(name)
            continue
        size = os.path.getsize(path)
        total += size
        entries.append({"name": name, "file": fname, "size": size, "sha256": sha256_of(path)})
    if missing:
        raise SystemExit("缺镜像: " + ", ".join(missing))
    return {
        "format": 1,
        "version": version,
        "channel": channel,
        "build_date": datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds"),
        "total_size": total,
        "base_url": base_url.rstrip("/") + "/",
        "note": note,
        "parts": entries,
        "signature": None,
    }


def put_json(s3, bucket, key, doc, cache=None):
    body = json.dumps(doc, ensure_ascii=False, indent=2).encode("utf-8")
    extra = {"ContentType": "application/json"}
    if cache:
        extra["CacheControl"] = cache
    s3.put_object(Bucket=bucket, Key=key, Body=body, **extra)
    print(f"  ↑ {key}  ({len(body)} B)")


def list_versions(s3, bucket, prefix):
    vers = set()
    p = s3.get_paginator("list_objects_v2")
    for page in p.paginate(Bucket=bucket, Prefix=prefix + "/", Delimiter="/"):
        for cp in page.get("CommonPrefixes", []):
            vers.add(cp["Prefix"].rstrip("/").rsplit("/", 1)[-1])
    return sorted(vers)


def prune(s3, bucket, prefix, keep, dry_run=False):
    vers = list_versions(s3, bucket, prefix)
    victims = vers[:-keep] if keep > 0 else vers
    if not victims:
        print(f"  保留策略 keep={keep}，当前 {len(vers)} 个版本，无需裁剪")
        return
    for v in victims:
        keys = []
        p = s3.get_paginator("list_objects_v2")
        for page in p.paginate(Bucket=bucket, Prefix=f"{prefix}/{v}/"):
            keys += [o["Key"] for o in page.get("Contents", [])]
        if dry_run:
            print(f"  [dry-run] 将删 {v}（{len(keys)} 个对象）")
            continue
        for k in keys:
            s3.delete_object(Bucket=bucket, Key=k)
        print(f"  − 已删旧版本 {v}（{len(keys)} 个对象）")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--parts", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--channel", default="stable")
    ap.add_argument("--bucket", default=None)
    ap.add_argument("--prefix", default="gk3-ota")
    ap.add_argument("--base-url", default=None, help="默认取 R2_PUBLIC_BASE，拼 <prefix>/<channel>/")
    ap.add_argument("--keep", type=int, default=2, help="保留最近 N 个版本的全量对象，0=全留")
    ap.add_argument("--index-only", action="store_true", help="只传清单，不传镜像")
    ap.add_argument("--note", default="")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    env = load_env()
    for k in ("R2_ENDPOINT", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
        if not env.get(k):
            raise SystemExit(f"缺凭据 {k}（写在 .secrets/r2.env）")
    bucket = a.bucket or env.get("R2_BUCKET") or "coloros"
    s3 = client(env)

    base = a.base_url or (env.get("R2_PUBLIC_BASE", "").rstrip("/") + f"/{a.prefix}/{a.channel}")
    if not base:
        raise SystemExit("缺公网前缀：给 --base-url 或 R2_PUBLIC_BASE")
    base = base.rstrip("/") + "/" + a.version

    doc = build_index(a.parts, a.version, a.channel, base, a.note)
    print(f"清单: {a.version}  13 分区  {doc['total_size']/2**30:.2f} GiB  base_url={base}")

    if not a.index_only and not a.dry_run:
        cfg = TransferConfig(multipart_threshold=64 << 20, multipart_chunksize=64 << 20, max_concurrency=6)
        for e in doc["parts"]:
            path, _ = find_image(a.parts, e["name"])
            key = f"{a.prefix}/{a.channel}/{a.version}/{e['file']}"
            print(f"  ↑ {key}  ({e['size']/2**20:.0f} MiB)")
            s3.upload_file(path, bucket, key, Config=cfg,
                           ExtraArgs={"ContentType": "application/octet-stream"})

    put_json(s3, bucket, f"{a.prefix}/{a.channel}/{a.version}/index.json", doc, cache="public, max-age=300")
    put_json(s3, bucket, f"{a.prefix}/{a.channel}/index.json", doc, cache="public, max-age=60")

    prune(s3, bucket, f"{a.prefix}/{a.channel}", a.keep, a.dry_run)
    print("完成。客户端地址:", f"{base.rsplit('/', 1)[0]}/../{a.channel}/index.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
