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
    ap.add_argument("--only", help="只处理这些逻辑分区（逗号分隔，如 my_manifest），用于小步试写")
    args = ap.parse_args(argv[1:])

    layout = json.load(open(args.layout, encoding="utf-8"))
    suffix = f"_{args.slot}"
    parts = [p for p in layout["partitions"] if p["name"].endswith(suffix)]
    if args.only:
        keep = {x.strip() for x in args.only.split(",") if x.strip()}
        parts = [p for p in parts if p["name"][: -len(suffix)] in keep]
    if not parts:
        print(f"布局里没有可用的 {suffix} 分区", file=sys.stderr)
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
    verify += ["[ $bad -eq 0 ] && echo VERIFY_B_OK || { echo VERIFY_B_FAILED; exit 1; }"]

    # 一键脚本：校验下载物 → 写入 → 回读 → （可选）切槽。
    # 切槽语义是实测出来的：update_engine_client --oplus_switch_slot=true 是“切到另一槽”的开关，
    # 在 a 上跑就进 b，在 b 上再跑就回 a，不需要 --oplus_switch_slot=false（实测该值写入后 bootloader 不理）。
    apply = [
        "#!/system/bin/sh",
        "# 由 tools/ota/slot_writer.py 生成：校验源镜像 → 写 " + args.slot + " 槽 → 回读比对 → 可选切槽",
        "# 用法：sh apply_" + args.slot + ".sh [switch]   （第二个参数 switch 时，校验通过后切到另一槽）",
        "set -e",
        'HERE=$(cd "$(dirname "$0")" && pwd)',
        'SRC=$(sed -n "s/^SRC=//p" "$HERE/write_' + args.slot + '.sh")',
        'SUP=/dev/block/by-name/super',
        "",
        'echo "== 1/4 源镜像 sha256"',
        "fail=0",
    ]
    for e in entries:
        if not e.get("sha256"):
            continue
        apply.append(
            f'got=$(sha256sum "$SRC/{e["file"]}" 2>/dev/null | cut -d" " -f1)\n'
            f'if [ "$got" = "{e["sha256"]}" ]; then echo "  OK   {e["file"]}"; else echo "  FAIL {e["file"]} $got"; fail=1; fi'
        )
    apply += [
        '[ $fail -eq 0 ] || { echo APPLY_ABORT_BAD_SOURCE; exit 1; }',
        'echo "== 2/4 写入 ' + args.slot + ' 槽（A 槽不动）"',
        'sh "$HERE/write_' + args.slot + '.sh"',
        'echo "== 3/4 回读校验"',
        'sh "$HERE/verify_' + args.slot + '.sh"',
        'echo "== 4/4 切槽"',
        '[ "${1:-}" = "switch" ] || { echo "APPLY_OK（未切槽；加 switch 参数才会切）"; exit 0; }',
        'update_engine_client --oplus_switch_slot=true',
        'echo "APPLY_SWITCHED 重启后生效：adb reboot"',
    ]

    rollback = [
        "#!/system/bin/sh",
        "# 切回另一槽（a↔b 反复可用）。真机上残留的切换请求会被 bootloader 消费掉，所以同一条命令就是“来回切”。",
        "update_engine_client --oplus_switch_slot=true",
        'echo "SLOT_TOGGLE_REQUESTED 重启后生效：adb reboot"',
    ]

    wpath = os.path.join(args.out, f"write_{args.slot}.sh")
    vpath = os.path.join(args.out, f"verify_{args.slot}.sh")
    apath = os.path.join(args.out, f"apply_{args.slot}.sh")
    rpath = os.path.join(args.out, "rollback.sh")
    open(wpath, "w", encoding="utf-8", newline="\n").write("\n".join(write) + "\n")
    os.chmod(wpath, 0o755)
    open(apath, "w", encoding="utf-8", newline="\n").write("\n".join(apply) + "\n")
    os.chmod(apath, 0o755)
    if not os.path.exists(rpath):
        open(rpath, "w", encoding="utf-8", newline="\n").write("\n".join(rollback) + "\n")
        os.chmod(rpath, 0o755)
    if all(e.get("sha256") for e in entries):
        open(vpath, "w", encoding="utf-8", newline="\n").write("\n".join(verify) + "\n")
        os.chmod(vpath, 0o755)
    else:
        print("  （dry-run：没有 --parts-dir，不生成 verify 脚本，清单里也没有 sha256）")

    print(f"槽 {args.slot}: {len(entries)} 个分区，合计 {man['total_bytes']/2**30:.2f} GiB")
    print(f"  manifest: {man_path}")
    print(f"  {wpath} / {vpath} / {apath}")
    print(f"  设备端镜像目录: {src_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
