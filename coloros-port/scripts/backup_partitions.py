#!/usr/bin/env python3
"""Back up the gaokun3 partitions needed for rollback.

Run from a Linux live USB while no Android partition is mounted. The tool
only reads blocks and creates a small manifest plus compressed images.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path


def run(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode:
        raise SystemExit(f"failed: {' '.join(command)}\n{result.stderr}")
    return result.stdout


def find_partition(disk: str, label: str) -> str:
    data = json.loads(run(["lsblk", "-J", "-b", "-o", "NAME,PATH,SIZE,TYPE,PARTLABEL,LABEL,MOUNTPOINTS"]))
    candidates = []

    def walk(items):
        for item in items:
            item["path"] = item.get("path") or f"/dev/{item['name']}"
            if item.get("path", "").startswith(disk) and item.get("type") == "part":
                if (item.get("partlabel") or item.get("label")) == label:
                    candidates.append(item["path"])
            walk(item.get("children", []))

    walk(data.get("blockdevices", []))
    if len(candidates) != 1:
        raise SystemExit(f"expected one {label!r} partition on {disk}, found {candidates}")
    return candidates[0]


def copy_device(source: str, target: Path) -> dict:
    target.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(["dd", f"if={source}", f"of={target}", "bs=16M", "status=progress", "conv=fsync"])
    if result.returncode:
        raise SystemExit(f"dd failed for {source}")
    digest = hashlib.sha256()
    with target.open("rb") as handle:
        while block := handle.read(8 * 1024 * 1024):
            digest.update(block)
    return {"source": source, "file": str(target), "bytes": target.stat().st_size, "sha256": digest.hexdigest()}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disk", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--partitions", nargs="+", default=["esp", "boot_a", "boot_b", "metadata", "misc", "super"])
    args = parser.parse_args(argv)
    args.output.mkdir(parents=True, exist_ok=True)
    records = []
    for name in args.partitions:
        source = find_partition(args.disk, name)
        target = args.output / f"{name}.img"
        if target.exists():
            raise SystemExit(f"refusing to overwrite {target}")
        print(f"BACKUP {name}: {source} -> {target}")
        records.append(copy_device(source, target))
    (args.output / "manifest.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
    print(f"DONE {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
