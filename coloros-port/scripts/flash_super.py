#!/usr/bin/env python3
"""Flash only the ColorOS super partition to a gaokun3 disk.

This is a deliberate narrow tool: it never touches ESP, boot, Windows,
userdata or metadata unless the caller separately asks for a data wipe.
It refuses to run without --write and --confirm-device gaokun3.

The program runs on Linux (or a Linux USB live system), not on Windows,
because it needs direct block-device access.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

EXPECTED_SUPER_BYTES = 12884901888


def run(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(f"command failed ({result.returncode}): {' '.join(command)}\n{result.stderr}")
    return result.stdout


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def block_devices() -> list[dict]:
    raw = run(["lsblk", "-J", "-b", "-o", "NAME,PATH,SIZE,TYPE,MODEL,TRAN,PARTLABEL,LABEL,MOUNTPOINTS"])
    data = json.loads(raw)
    result = []

    def walk(items):
        for item in items:
            item["path"] = item.get("path") or f"/dev/{item['name']}"
            if item.get("type") == "part":
                item["partlabel"] = item.get("partlabel") or item.get("label")
            result.append(item)
            walk(item.get("children", []))

    walk(data.get("blockdevices", []))
    return result


def partition_path(disk: str, name: str) -> str:
    entries = block_devices()
    disk_entry = next((item for item in entries if item["path"] == disk), None)
    if not disk_entry:
        raise SystemExit(f"disk not found: {disk}")
    for item in entries:
        if item.get("type") == "part" and item.get("path", "").startswith(disk):
            label = item.get("partlabel") or item.get("label")
            if label == name:
                return item["path"]
    raise SystemExit(f"partition {name!r} not found on {disk}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disk", required=True, help="whole disk, e.g. /dev/nvme0n1")
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--confirm-device", required=True)
    parser.add_argument("--report", type=Path, default=Path("reports/flash.json"))
    args = parser.parse_args(argv)
    if args.confirm_device != "gaokun3":
        parser.error("--confirm-device must be gaokun3")
    if not args.image.is_file():
        parser.error(f"image not found: {args.image}")
    size = args.image.stat().st_size
    if size != EXPECTED_SUPER_BYTES:
        parser.error(f"super size {size:,} does not match expected {EXPECTED_SUPER_BYTES:,}")
    if not re.fullmatch(r"/dev/[A-Za-z0-9._/-]+", args.disk):
        parser.error("--disk must be an explicit /dev path")
    if not shutil.which("lsblk"):
        parser.error("lsblk is required")
    part = partition_path(args.disk, "super")
    report = {
        "disk": args.disk,
        "partition": part,
        "image": str(args.image.resolve()),
        "bytes": size,
        "sha256": sha256(args.image),
        "write": bool(args.write),
    }
    print(json.dumps(report, indent=2))
    if not args.write:
        print("DRY RUN: pass --write to flash. No data was changed.")
        return 0
    if os.geteuid() != 0:
        raise SystemExit("writing a block device requires root")
    # The image is exactly 12 GiB and maps only to the super partition.
    with args.image.open("rb") as src, open(part, "wb") as dst:
        written = 0
        while block := src.read(16 * 1024 * 1024):
            dst.write(block)
            written += len(block)
        dst.flush()
        os.fsync(dst.fileno())
    report["written"] = written
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"WROTE {written:,} bytes to {part}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
