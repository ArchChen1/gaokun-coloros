#!/usr/bin/env python3
"""把 payload 路线的发版文件传到 Cloudflare R2。

只做一件事：上传 payload.bin / payload.bin.properties（可选 index.json），
分片并发 + 断点重试。dd 分区布局走 tools/ota/r2_publish.py，两者互不重叠。

凭据：<repo>/.secrets/r2.env（R2_ENDPOINT / R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY /
      R2_BUCKET / R2_PUBLIC_BASE），环境变量可覆盖。

布局：
    gk3-ota/<version>/payload.bin
    gk3-ota/<version>/payload.bin.properties

用法：
    # 只看远端当前状态，不传
    python tools/ota/r2_put.py --version OPD2513_11.C.17_1170_202611262015 --check

    # 上传（默认并发 4，分片 32 MiB，失败自动重试 3 次）
    python tools/ota/r2_put.py --version OPD2513_11.C.17_1170_202611262015 \
        --payload work/payload_none_v2/payload.bin
"""
import argparse
import os
import sys

import boto3
from boto3.s3.transfer import TransferConfig
from botocore.config import Config
from botocore.exceptions import ClientError

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ENV_FILE = os.path.join(ROOT, ".secrets", "r2.env")
PREFIX = "gk3-ota"


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
        config=Config(retries={"max_attempts": 5, "mode": "standard"}, max_pool_connections=8),
    )


def remote_size(s3, bucket, key):
    try:
        return s3.head_object(Bucket=bucket, Key=key)["ContentLength"]
    except ClientError as e:
        if e.response["Error"]["Code"] in ("404", "NoSuchKey", "NotFound"):
            return None
        raise


def put(s3, bucket, key, path, cfg):
    size = os.path.getsize(path)
    have = remote_size(s3, bucket, key)
    if have == size:
        print("  跳过（远端已同尺寸）: %s" % key)
        return False
    print("  上传 %s  %.2f GiB -> s3://%s/%s" % (path, size / 2 ** 30, bucket, key))
    s3.upload_file(path, bucket, key, Config=cfg,
                   Callback=_progress(size))
    got = remote_size(s3, bucket, key)
    if got != size:
        raise SystemExit("尺寸不一致：远端 %s / 本地 %s" % (got, size))
    print("  OK %s  %d B" % (key, size))
    return True


def _progress(total):
    step = [0]

    def cb(n):
        step[0] += n
        pct = step[0] * 100 // total
        if pct != cb.last:
            cb.last = pct
            print("\r    %3d%%  %.2f/%.2f GiB" % (pct, step[0] / 2 ** 30, total / 2 ** 30), end="", flush=True)
            if pct >= 100:
                print()
    cb.last = -1
    return cb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--payload", default="", help="payload.bin 路径")
    ap.add_argument("--props", default="", help="properties 路径（默认与 payload 同目录同名 + .properties）")
    ap.add_argument("--index", default="", help="可选：一并上传 index.json 到 gk3-ota/<version>/")
    ap.add_argument("--check", action="store_true", help="只查远端，不上传")
    ap.add_argument("--concurrency", type=int, default=4)
    ap.add_argument("--chunk-mb", type=int, default=32)
    a = ap.parse_args()

    env = load_env()
    s3 = client(env)
    bucket = env["R2_BUCKET"]
    print("bucket=%s endpoint=%s" % (bucket, env["R2_ENDPOINT"]))

    keys = []
    if a.payload:
        if not os.path.isfile(a.payload):
            raise SystemExit("找不到 %s" % a.payload)
        keys.append(("%s.bin" % "payload", a.payload))
    if a.props:
        keys.append(("payload.bin.properties", a.props))
    elif a.payload:
        p = a.payload + ".properties"
        if os.path.isfile(p):
            keys.append(("payload.bin.properties", p))
    if a.index:
        keys.append(("index.json", a.index))

    for name, path in keys:
        key = "%s/%s/%s" % (PREFIX, a.version, name)
        have = remote_size(s3, bucket, key)
        print("  %s : 远端 %s" % (key, "无" if have is None else "%d B" % have))

    if a.check:
        return

    cfg = TransferConfig(multipart_threshold=8 * 2 ** 20, multipart_chunksize=a.chunk_mb * 2 ** 20,
                         max_concurrency=a.concurrency, use_threads=True)
    for name, path in keys:
        key = "%s/%s/%s" % (PREFIX, a.version, name)
        put(s3, bucket, key, path, cfg)
    base = env.get("R2_PUBLIC_BASE") or "https://ota.cenmin.cn/%s/%s/" % (PREFIX, a.version)
    print("完成。URL 前缀：%s" % base)


if __name__ == "__main__":
    main()
