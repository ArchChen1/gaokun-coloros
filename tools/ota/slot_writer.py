#!/usr/bin/env python3
"""从 super 槽位布局生成“把 B 槽写满”的设备端脚本（不联网、不签名、不动 A 槽）。

用法：

    # 1. 取布局（设备侧 lpdump 不需要 root）
    adb shell lpdump /dev/block/by-name/super > lpdump.txt
    python3 tools/ota/lp_layout.py lpdump.txt --json lp.json

    # 2. 生成脚本与清单（--parts-dir 指向 current/parts）
    python3 tools/ota/slot_writer.py lp.json --slot b --parts-dir /home/you/gk3-build/current/parts --out ota/

产物：
    ota/write_b.sh        设备端写入脚本（需要 root；dd 到 super 的 B 区段）
    ota/verify_b.sh       设备端回读校验（逐分区 dd 出来算 sha256）
    ota/ota-manifest.json 分区清单：名字、扇区区间、字节数、sha256、推送路径

要点：
- 分区大小来自 metadata，镜像必须与之严格相等（我们的 parts 是 lpmake 按文件大小分配的，天然相等）。
- 只写 *_b 的区间，A 槽扇区不碰，所以刷坏 B 也能回到 A。
- 写入用 `dd bs=512 seek=<扇区> conv=notrunc`，Android 自带 toybox dd 就够，不需要额外二进制。
"""
import argparse
import hashlib
import json
import os
import sys

# 逻辑分区名 → 构建产物文件名（与 build/current_build.sh 的 names 对齐）
DEFAULT_FILES = {
    "system": "system.erofs",
    "system_ext": "system_ext_a.img",
    "product": "product_a.img",
    "vendor": "vendor.img",
    "odm": "odm.erofs",
    "my_product": "my_product.erofs",
    "my_stock": "my_stock.erofs",
    "my_manifest": "my_manifest_a.img",
    "my_region": "my_region_a.img",
    "my_engineering": "my_engineering_a.img",
    "my_heytap": "my_heytap_a.img",
    "my_carrier": "my_carrier_a.img",
    "my_bigball": "my_bigball_a.img",
}
SECTOR = 512


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="生成 B 槽写入脚本")
    ap.add_argument("layout", help="lp_layout.py --json 产出的布局 JSON")
    ap.add_argument("--slot", default="b", choices=["a", "b"])
    ap.add_argument("--parts-dir", help="分区镜像所在目录（current/parts）；不给就只做 dry-run")
    ap.add_argument("--out", default="ota", help="输出目录")
    args = ap.parse_args(argv[1:])

    layout = json.load(open(args.layout, encoding="utf-8"))
    suffix = f"_{args.slot}"
    parts = [p for p in layout["partitions"] if p["name"].endswith(suffix)]
    if not parts:
        print(f"布局里没有 {suffix} 分区", file=sys.stderr)
        return 1

    os.makedirs(args.out, exist_ok=True)
    entries = []
    problems = []
    for p in parts:
        base = p["name"][: -len(suffix)]
        fname = DEFAULT_FILES.get(base)
        ext = p["extents"]
        if len(ext) != 1 or ext[0]["type"] != "linear" or ext[0]["target"] != layout["block"].get("name", "super"):
            problems.append(f"{p['name']}: extent 不是单段 linear super（{ext}）")
            continue
        start = ext[0]["target_start_sector"]
        sectors = ext[0]["num_sectors"]
        e = {"partition": p["name"], "file": fname, "start_sector": start,
             "sectors": sectors, "bytes": p["bytes"]}
        if args.parts_dir and fname:
            path = os.path.join(args.parts_dir, fname)
            if not os.path.exists(path):
                problems.append(f"{p['name']}: 缺镜像 {path}")
            else:
                size = os.path.getsize(path)
                if size != p["bytes"]:
                    problems.append(f"{p['name']}: 镜像 {size} B != metadata {p['bytes']} B")
                e["sha256"] = sha256(path)
                e["size_on_disk"] = size
        entries.append(e)

    if problems:
        for x in problems:
            print(f"FAIL {x}", file=sys.stderr)
        return 1

    man = {
        "generated_by": "tools/ota/slot_writer.py",
        "target_slot": args.slot,
        "super": {"device": "/dev/block/by-name/super",
                  "first_sector": layout["block"].get("first_sector"),
                  "size_bytes": layout["block"].get("size_bytes")},
        "total_bytes": sum(e["bytes"] for e in entries),
        "partitions": entries,
    }
    man_path = os.path.join(args.out, "ota-manifest.json")
    json.dump(man, open(man_path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

    src_dir = "/data/local/tmp/gk3-ota/" + args.slot
    write = [
        "#!/system/bin/sh",
        "# 由 tools/ota/slot_writer.py 生成：只写 super 的 " + args.slot + " 槽区间，A 槽不动。",
        "set -e",
        "SUP=/dev/block/by-name/super",
        "SRC=" + src_dir,
        "",
        "w() {  # <文件> <起始扇区> <扇区数>",
        "  echo \"  $1 -> sector $2 ($3 sectors)\"",
        "  dd if=\"$SRC/$1\" of=\"$SUP\" bs=512 seek=\"$2\" count=\"$3\" conv=notrunc 2>/dev/null",
        "}",
        "",
    ]
    for e in entries:
        write.append(f'w {e["file"]} {e["start_sector"]} {e["sectors"]}')
    write += ["sync", "echo WRITE_B_DONE"]

    verify = [
        "#!/system/bin/sh",
        "# 逐分区回读，和 ota-manifest.json 里的 sha256 对比",
        "SUP=/dev/block/by-name/super",
        "bad=0",
    ]
    for e in entries:
        verify.append(
            f'got=$(dd if="$SUP" bs=512 skip={e["start_sector"]} count={e["sectors"]} 2>/dev/null | sha256sum | cut -d" " -f1)\n'
            f'if [ "$got" = "{e.get("sha256", "")}" ]; then echo "  OK   {e["partition"]}"; else echo "  FAIL {e["partition"]} $got"; bad=1; fi'
        )
    verify += ["[ $bad -eq 0 ] && echo VERIFY_B_OK || echo VERIFY_B_FAILED"]

    wpath = os.path.join(args.out, "write_b.sh")
    vpath = os.path.join(args.out, "verify_b.sh")
    open(wpath, "w", encoding="utf-8", newline="\n").write("\n".join(write) + "\n")
    os.chmod(wpath, 0o755)
    if all(e.get("sha256") for e in entries):
        open(vpath, "w", encoding="utf-8", newline="\n").write("\n".join(verify) + "\n")
        os.chmod(vpath, 0o755)
    else:
        print("  （dry-run：没有 --parts-dir，不生成 verify_b.sh，清单里也没有 sha256）")

    print(f"槽 {args.slot}: {len(entries)} 个分区，合计 {man['total_bytes']/2**30:.2f} GiB")
    print(f"  manifest: {man_path}")
    print(f"  {wpath} / {vpath}")
    print(f"  设备端镜像目录: {src_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
