#!/usr/bin/env python3
"""按 manifest 账本校验 13 个分区产物；或从一份目录写出账本。

存在的原因：manifest.json 早就记了 path+sha，但没有任何东西会去核对它——
`build/current_pack.sh` 只读 path、`tools/ota/make_payload.py` 干脆只吃目录。
于是「补丁丢了」（vendor 退回未打补丁版本、system 用基座版、my_engineering 少了证书）
这几种事故都不会被挡住，只能靠人记。

    # 出包/出 payload 之前必跑（任一 FAIL 退出码 1）
    python3 tools/ota/parts_manifest.py verify --manifest /home/cenmin/coloros-build/current/manifest.json

    # 从一份目录生成账本（--note 写进 ledger 的 note 字段）
    python3 tools/ota/parts_manifest.py write --parts E:/gk3-coloros/work/bdump \
        --out work/manifest.json --note "设备 slot _b 原样 dump"

分区名与文件名不一致的地方（system.erofs / odm.erofs / my_*.erofs）由 NAMES 表兜住。
"""
import argparse
import hashlib
import json
import os
import sys

NAMES = ["system", "system_ext", "product", "vendor", "odm", "my_product", "my_stock",
         "my_manifest", "my_region", "my_engineering", "my_heytap", "my_carrier", "my_bigball"]

# 目录模式下允许的文件名（逻辑名 -> 可能出现的文件名，按顺序尝试）
FILENAMES = {
    "system": ["system.erofs", "system.img", "system_b.img", "system_a.img"],
    "system_ext": ["system_ext.img", "system_ext_b.img", "system_ext_a.img"],
    "product": ["product.img", "product_b.img", "product_a.img"],
    "vendor": ["vendor.img", "vendor_b.img", "vendor_a.img"],
    "odm": ["odm.erofs", "odm.img", "odm_b.img", "odm_a.img"],
    "my_product": ["my_product.erofs", "my_product.img", "my_product_b.img", "my_product_a.img"],
    "my_stock": ["my_stock.erofs", "my_stock.img", "my_stock_b.img", "my_stock_a.img"],
    "my_manifest": ["my_manifest.img", "my_manifest_b.img", "my_manifest_a.img"],
    "my_region": ["my_region.img", "my_region_b.img", "my_region_a.img"],
    "my_engineering": ["my_engineering.img", "my_engineering_b.img", "my_engineering_a.img"],
    "my_heytap": ["my_heytap.img", "my_heytap_b.img", "my_heytap_a.img"],
    "my_carrier": ["my_carrier.img", "my_carrier_b.img", "my_carrier_a.img"],
    "my_bigball": ["my_bigball.img", "my_bigball_b.img", "my_bigball_a.img"],
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def resolve(path, base):
    if os.path.isabs(path) or not base:
        return path
    return os.path.join(base, path)


def cmd_verify(a):
    man = json.load(open(a.manifest, encoding="utf-8"))
    parts = man.get("parts", {})
    bad = []
    missing_names = [n for n in NAMES if n not in parts]
    for n in NAMES:
        p = parts.get(n)
        if not p:
            bad.append((n, "账本里没有这个分区"))
            continue
        path = resolve(p["path"], a.base)
        if not os.path.isfile(path):
            bad.append((n, f"文件不存在 {path}"))
            continue
        size = os.path.getsize(path)
        if "bytes" in p and size != p["bytes"]:
            bad.append((n, f"大小不符 {size} != {p['bytes']}"))
            continue
        got = sha256(path)
        if got != p.get("sha256"):
            bad.append((n, f"sha 不符 {got[:16]}… != {str(p.get('sha256'))[:16]}…"))
            continue
        print(f"  OK   {n:<14} {size:>12} {got[:16]}…  {path}")
    if missing_names:
        print("  缺分区: " + ", ".join(missing_names), file=sys.stderr)
    for n, why in bad:
        print(f"  FAIL {n:<14} {why}", file=sys.stderr)
    if bad:
        print(f"VERIFY_FAILED: {len(bad)} 项不通过（账本 = {a.manifest}）", file=sys.stderr)
        return 1
    print(f"账本校验通过：13/13，generated={man.get('generated', '?')}")
    return 0


def cmd_write(a):
    parts, bad = {}, []
    for n in NAMES:
        path = None
        for fn in FILENAMES[n]:
            cand = os.path.join(a.parts, fn)
            if os.path.isfile(cand):
                path = cand
                break
        if not path:
            bad.append(n)
            continue
        parts[n] = {"path": os.path.abspath(path), "bytes": os.path.getsize(path), "sha256": sha256(path)}
    if bad:
        print("缺少产物: " + ", ".join(bad), file=sys.stderr)
        return 1
    out = {"generated": __import__("time").strftime("%Y-%m-%dT%H:%M:%S"), "note": a.note or "",
           "parts": parts}
    with open(a.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"写出账本 {a.out}（13 个分区）")
    return 0


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("verify", help="按账本核对产物")
    v.add_argument("--manifest", required=True)
    v.add_argument("--base", default="", help="相对路径的基准目录")
    v.set_defaults(fn=cmd_verify)
    w = sub.add_parser("write", help="从目录生成账本")
    w.add_argument("--parts", required=True)
    w.add_argument("--out", required=True)
    w.add_argument("--note", default="")
    w.set_defaults(fn=cmd_write)
    a = ap.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
