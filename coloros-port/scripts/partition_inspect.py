#!/usr/bin/env python3
"""Inspect raw, Android sparse and liblp (super) images.

Examples:
    python scripts/partition_inspect.py inputs/system.img
    python scripts/partition_inspect.py inputs/super.img --partitions
    python scripts/partition_inspect.py inputs/super.img --extract system out/system.img

Only read operations are performed unless --extract names an output path.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib_android import (  # noqa: E402
    describe_raw,
    describe_sparse,
    detect_filesystem,
    is_sparse,
    read_lp_metadata,
)


def inspect_lp(path: Path) -> dict:
    geometry, metadata = read_lp_metadata(path)
    partitions = []
    for part in metadata.partitions:
        partitions.append({
            "name": part.name,
            "attributes": part.attributes,
            "group_index": part.group_index,
            "num_extents": part.num_extents,
            "bytes": sum(extent.num_sectors for extent in part.extents) * 512,
            "extents": [
                {
                    "start_sector": extent.target_data,
                    "sectors": extent.num_sectors,
                    "target_type": extent.target_type,
                }
                for extent in part.extents
            ],
        })
    return {
        "path": str(path.resolve()),
        "bytes": path.stat().st_size,
        "lp": True,
        "major": metadata.major,
        "minor": metadata.minor,
        "header_size": metadata.header_size,
        "header_flags": metadata.header_flags,
        "slot": metadata.slot,
        "geometry": geometry,
        "groups": [
            {"name": group.name, "flags": group.flags, "maximum_size": group.maximum_size}
            for group in metadata.groups
        ],
        "partitions": partitions,
    }


def inspect_image(path: Path, as_lp: bool) -> dict:
    if as_lp or path.stat().st_size >= 8192:
        try:
            return inspect_lp(path)
        except ValueError:
            pass
    if is_sparse(path):
        info = describe_sparse(path)
        info.update({"path": str(path.resolve()), "bytes": info["raw_bytes"], "lp": False})
        return info
    info = describe_raw(path)
    info.update({
        "path": str(path.resolve()),
        "bytes": info["raw_bytes"],
        "lp": False,
        "filesystem": detect_filesystem(path),
    })
    return info


def print_human(report: dict, show_partitions: bool) -> None:
    print(f"FILE   {report['path']}")
    print(f"SIZE   {report['bytes']:,} bytes")
    if report.get("lp"):
        geometry = report["geometry"]
        print(f"SUPER  liblp {report['major']}.{report['minor']}, metadata slot {report['slot']}")
        print(f"      metadata_max={geometry['max_metadata_bytes']:,} slots={geometry['metadata_slots']}")
        print(f"GROUPS {len(report['groups'])}  PARTS {len(report['partitions'])}")
        if show_partitions:
            for part in report["partitions"]:
                state = "empty" if part["bytes"] == 0 else f"{part['bytes']:,} bytes"
                print(f"  {part['name']:<22} {state:>16}  extents={part['num_extents']}")
                for extent in part["extents"]:
                    print(f"      offset={extent['start_sector'] * 512:>12,}  len={extent['sectors'] * 512:>12,}")
    elif report.get("sparse"):
        print(f"SPARSE v{report['major']}.{report['minor']}  raw={report['raw_bytes']:,}")
        print(f"      block={report['block_size']} chunks={report['total_chunks']} kinds={report['chunk_kinds']}")
    else:
        print(f"RAW    {report['raw_bytes']:,} bytes  filesystem={report.get('filesystem', 'unknown')}")


def extract_lp_partition(path: Path, name: str, output: Path) -> dict:
    _, metadata = read_lp_metadata(path)
    part = metadata.partition(name)
    if part is None:
        available = ", ".join(item.name for item in metadata.partitions)
        raise SystemExit(f"partition {name!r} not found; available: {available}")
    if part.num_extents != 1:
        raise SystemExit(f"{name}: {part.num_extents} extents are not supported by this extractor")
    extent = part.extents[0]
    offset = extent.target_data * 512
    length = extent.num_sectors * 512
    output.parent.mkdir(parents=True, exist_ok=True)
    with path.open("rb") as src, output.open("wb") as dst:
        src.seek(offset)
        remaining = length
        while remaining:
            block = src.read(min(8 * 1024 * 1024, remaining))
            if not block:
                raise SystemExit("unexpected end of super image while extracting")
            dst.write(block)
            remaining -= len(block)
    return {"partition": name, "output": str(output), "offset": offset, "bytes": length}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--partitions", action="store_true", help="list liblp partitions and extents")
    parser.add_argument("--json", type=Path, help="write the full report as JSON")
    parser.add_argument("--extract", nargs=2, metavar=("PARTITION", "OUTPUT"), help="extract one liblp partition")
    parser.add_argument("--force-lp", action="store_true", help="do not fall back to sparse/raw detection")
    args = parser.parse_args(argv)
    if not args.image.is_file():
        parser.error(f"not a file: {args.image}")
    if args.extract:
        result = extract_lp_partition(args.image, args.extract[0], Path(args.extract[1]))
        print(f"EXTRACTED {result['partition']} -> {result['output']} ({result['bytes']:,} bytes at {result['offset']:,})")
        return 0
    report = inspect_image(args.image, args.force_lp)
    print_human(report, args.partitions)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"REPORT {args.json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
