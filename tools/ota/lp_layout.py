#!/usr/bin/env python3
"""解析 AOSP `lpdump` 的输出，得到 super 的逻辑分区 / 槽位布局（JSON）。

为什么要这一步：给 B 槽写镜像要精确知道每个逻辑分区在 `super` 上的扇区区间，
手抄 `lpdump` 迟早抄错。设备上 `lpdump` 不需要 root，所以布局可以从真机现取：

    adb shell lpdump /dev/block/by-name/super > lpdump.txt
    python3 tools/ota/lp_layout.py lpdump.txt --json layout.json

    python3 tools/ota/lp_layout.py lpdump.txt            # 人读的摘要
    python3 tools/ota/lp_layout.py lpdump.txt --slot b   # 只看 B 槽

扇区单位是 512 字节（LP metadata 与 lpdump 都用这个单位）。
"""
import argparse
import json
import re
import sys
from typing import Any

EXTENT_RE = re.compile(r"^\s+(\d+) \.\. (\d+) (linear|zero)(?:\s+(\S+)\s+(\d+))?\s*$")
LAYOUT_RE = re.compile(r"^super: (\d+) \.\. (\d+): (\S+) \((\d+) sectors\)\s*$")
PART_START_RE = re.compile(r"^\s+Name: (\S+)\s*$")


class LpLayoutError(Exception):
    pass


def parse(text: str) -> dict[str, Any]:
    slots: list[dict[str, Any]] = []
    cur: dict[str, Any] | None = None
    part: dict[str, Any] | None = None
    section = None

    def flush_part():
        nonlocal part
        if part is not None and cur is not None:
            part["sectors"] = sum(e["num_sectors"] for e in part["extents"])
            part["bytes"] = part["sectors"] * 512
            cur["partitions"].append(part)
        part = None

    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        m = re.match(r"^Slot (\d+):", line)
        if m:
            flush_part()
            cur = {
                "slot": int(m.group(1)),
                "metadata_version": "",
                "metadata_size": 0,
                "metadata_max_size": 0,
                "metadata_slot_count": 0,
                "header_flags": [],
                "partitions": [],
                "layout": [],
                "block": {},
                "groups": [],
                "snapshot": {},
            }
            slots.append(cur)
            section = None
            continue
        if cur is None:
            continue

        if line.startswith("Partition table:"):
            section = "partitions"; continue
        if line.startswith("Super partition layout:"):
            flush_part(); section = "layout"; continue
        if line.startswith("Block device table:"):
            flush_part(); section = "block"; continue
        if line.startswith("Group table:"):
            flush_part(); section = "groups"; continue
        if line.startswith("Snapshot state:") or line.startswith("---------------") or line.startswith("----------"):
            continue

        if section == "partitions":
            pm = PART_START_RE.match(line)
            if pm:
                flush_part()
                part = {"name": pm.group(1), "group": "", "attributes": [], "extents": [], "sectors": 0, "bytes": 0}
                continue
            if part is not None:
                if line.strip().startswith("Group:"):
                    part["group"] = line.split(":", 1)[1].strip()
                elif line.strip().startswith("Attributes:"):
                    val = line.split(":", 1)[1].strip()
                    part["attributes"] = [] if val == "none" else [a.strip() for a in val.split(",")]
                em = EXTENT_RE.match(line)
                if em:
                    part["extents"].append({
                        "start_sector": int(em.group(1)),
                        "num_sectors": int(em.group(2)) - int(em.group(1)) + 1,
                        "type": em.group(3),
                        "target": em.group(4) or "",
                        "target_start_sector": int(em.group(5)) if em.group(5) else 0,
                    })
            continue

        if section == "layout":
            lm = LAYOUT_RE.match(line)
            if lm:
                cur["layout"].append({
                    "partition": lm.group(3),
                    "start_sector": int(lm.group(1)),
                    "end_sector": int(lm.group(2)),
                    "sectors": int(lm.group(4)),
                })
            continue

        if section == "block":
            s = line.strip()
            if s.startswith("Partition name:"):
                cur["block"]["name"] = s.split(":", 1)[1].strip()
            elif s.startswith("First sector:"):
                cur["block"]["first_sector"] = int(s.split(":", 1)[1].strip())
            elif s.startswith("Size:"):
                cur["block"]["size_bytes"] = int(s.split(":", 1)[1].split()[0])
            continue

        if section == "groups":
            s = line.strip()
            if s.startswith("Name:"):
                cur["groups"].append({"name": s.split(":", 1)[1].strip(), "max_bytes": 0})
            elif s.startswith("Maximum size:") and cur["groups"]:
                cur["groups"][-1]["max_bytes"] = int(s.split(":", 1)[1].split()[0])
            continue

        s = line.strip()
        if ":" in s and not s.startswith("--"):
            k, v = s.split(":", 1)
            k, v = k.strip(), v.strip()
            if k == "Metadata version":
                cur["metadata_version"] = v
            elif k == "Metadata size":
                cur["metadata_size"] = int(v.split()[0])
            elif k == "Metadata max size":
                cur["metadata_max_size"] = int(v.split()[0])
            elif k == "Metadata slot count":
                cur["metadata_slot_count"] = int(v)
            elif k == "Header flags":
                cur["header_flags"] = [f.strip() for f in v.split(",") if f.strip() and v != "none"]
            elif k in ("Current slot", "Update state", "Boot indicator", "Using snapuserd",
                       "Using userspace snapshots", "Using io_uring", "Using o_direct",
                       "Using skip_verification"):
                cur["snapshot"][k] = v

    flush_part()
    if not slots:
        raise LpLayoutError("没解析到任何 Slot，输入不是 lpdump 的输出？")
    return slots[0]


def slot_of(partition: str) -> str:
    return partition.rsplit("_", 1)[-1] if partition.endswith(("_a", "_b")) else ""


def summarise(layout: dict[str, Any], only_slot: str | None = None) -> str:
    out = []
    blk = layout["block"]
    out.append(f"metadata {layout['metadata_version']}  flags={','.join(layout['header_flags']) or 'none'}"
               f"  metadata_slots={layout['metadata_slot_count']}")
    out.append(f"block {blk.get('name')}  first_sector={blk.get('first_sector')}  size={blk.get('size_bytes')} B")
    for slot in ("a", "b"):
        parts = [p for p in layout["partitions"] if slot_of(p["name"]) == slot]
        if not parts:
            continue
        total = sum(p["sectors"] for p in parts)
        end = max(e["start_sector"] + e["num_sectors"] for p in parts for e in p["extents"] if e["type"] == "linear")
        out.append(f"槽 {slot}: {len(parts)} 个分区, {total} sectors = {total*512/2**30:.2f} GiB, 末端 sector {end}")
    if only_slot:
        parts = [p for p in layout["partitions"] if slot_of(p["name"]) == only_slot]
        out.append(f"-- 槽 {only_slot} 明细（sector 512 B）--")
        for p in sorted(parts, key=lambda p: p["extents"][0]["target_start_sector"] if p["extents"] else 0):
            for e in p["extents"]:
                out.append(f"  {p['name']:<20} super {e['target_start_sector']:>10} +{e['num_sectors']:>9}"
                           f"  = {e['num_sectors']*512/2**20:8.1f} MiB")
    return "\n".join(out)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="解析 lpdump 输出为 super 槽位布局")
    ap.add_argument("lpdump", help="lpdump 的输出文件（或 - 表示 stdin）")
    ap.add_argument("--json", metavar="PATH", help="把布局写成 JSON")
    ap.add_argument("--slot", choices=["a", "b"], help="只显示某个槽的分区明细")
    args = ap.parse_args(argv[1:])

    text = sys.stdin.read() if args.lpdump == "-" else open(args.lpdump, encoding="utf-8", errors="replace").read()
    layout = parse(text)
    print(summarise(layout, args.slot))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(layout, f, ensure_ascii=False, indent=2)
        print(f"json: {args.json}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except LpLayoutError as e:
        print(f"FAIL {e}", file=sys.stderr)
        sys.exit(1)
