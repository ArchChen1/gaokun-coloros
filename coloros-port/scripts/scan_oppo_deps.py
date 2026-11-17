#!/usr/bin/env python3
"""Scan ColorOS system images for OPPO-private service dependencies.

Input is an extracted directory (peak-readable) or a directory tree of files
that came from system/system_ext/product/my_*.  The scanner looks for
waitForService / checkService strings and known OPPO interfaces in ELF and
DEX-like files; it does not execute anything.

Example:
    python scripts/scan_oppo_deps.py work/parts/system --json reports/oppo-deps.json
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

INTERFACES = [
    "IEngineer",
    "IDisplayColorFeature",
    "IMixLut3D",
    "IIris",
    "IPeManager",
    "IFace",
    "ICharger",
    "IThermal",
    "IPower",
    "IMisc",
    "IGameOpt",
    "ITouch",
    "OplusEngineerFwService",
    "OplusDisplayFeature",
    "OplusAudio",
]

WAIT_MARKERS = ["waitForService", "checkService", "AServiceManager_waitForService"]
OPPO_SERVICE_BYTES = re.compile(rb"(?:vendor|oplus|oppo)\.[A-Za-z0-9_.]{3,120}")


def scan_file(path: Path) -> dict:
    try:
        data = path.read_bytes()
    except OSError as exc:
        return {"path": str(path), "error": str(exc)}
    interfaces = [name for name in INTERFACES if name.encode() in data]
    waits = [marker for marker in WAIT_MARKERS if marker.encode() in data]
    services = sorted({match.group(0).decode("ascii", "replace") for match in OPPO_SERVICE_BYTES.finditer(data)})
    if not interfaces and not waits and not services:
        return {}
    offsets = {}
    for name in interfaces + waits:
        at = data.find(name.encode())
        if at >= 0:
            context = data[max(0, at - 48):at + len(name) + 64]
            offsets[name] = {"offset": at, "context": context.decode("latin-1", "replace")}
    return {
        "path": str(path),
        "bytes": len(data),
        "interfaces": interfaces,
        "wait_markers": waits,
        "services": services[:80],
        "hits": offsets,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("--json", type=Path, default=Path("reports/oppo-deps.json"))
    args = parser.parse_args(argv)
    if not args.root.exists():
        parser.error(f"path not found: {args.root}")
    results = []
    if args.root.is_file():
        result = scan_file(args.root)
        if result:
            results.append(result)
    else:
        for path in args.root.rglob("*"):
            if not path.is_file():
                continue
            result = scan_file(path)
            if result:
                results.append(result)
    results.sort(key=lambda item: item["path"])
    summary = {
        "root": str(args.root.resolve()),
        "files": len(results),
        "interfaces": sorted({name for item in results for name in item.get("interfaces", [])}),
        "wait_files": [item["path"] for item in results if item.get("wait_markers")],
        "results": results,
    }
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"FILES {len(results)}  INTERFACES {len(summary['interfaces'])}")
    for name in summary["interfaces"]:
        print(f"  {name}")
    print(f"WAIT  {len(summary['wait_files'])} files")
    for path in summary["wait_files"][:40]:
        print(f"  {path}")
    print(f"REPORT {args.json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
