#!/usr/bin/env python3
"""Repack a gaokun3 super image with ColorOS partition images.

Geometry, metadata slots, group layout, first logical sector and virtual A/B
flags come from the baseline super. Only selected logical partitions are
relocated. Partitions not selected keep their existing extents, which is how
the gaokun3 vendor partition is preserved.

liblp layout (bytes):
    0                    4096   reserved
    4096                 4096   geometry
    8192                 4096   geometry backup
    12288                N*max  primary metadata slots
    12288 + N*max        N*max  backup metadata slots
    first_logical_sector*512    partition data (from the block-device table)

Examples:
    python scripts/super_repack.py \
        --template out/baseline-super.img --images out/parts \
        --partition system --partition system_ext --partition product \
        --slot-suffix _a --output out/super.raw.img
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib_android import LP_METADATA_OFFSET, SuperWriter, is_sparse, read_lp_metadata  # noqa: E402

ALIGN = 1024 * 1024


def align_up(value: int) -> int:
    return (value + ALIGN - 1) // ALIGN * ALIGN


def block_device_info(template: Path) -> dict:
    with template.open("rb") as handle:
        handle.seek(LP_METADATA_OFFSET)
        blob = handle.read(65536)
    if len(blob) < 180:
        raise SystemExit("template metadata is too small")
    magic, _, _, header_size = struct.unpack_from("<IHHI", blob, 0)
    if magic != 0x414C5030:
        raise SystemExit("template liblp magic mismatch")
    descriptors = [struct.unpack_from("<III", blob, 80 + i * 12) for i in range(4)]
    boff, bcount, bsize = descriptors[3]
    if bcount < 1 or bsize != 64:
        raise SystemExit(f"invalid block-device table: count={bcount} entry={bsize}")
    first, alignment, alignment_offset, super_size, raw_name, flags = struct.unpack_from(
        "<QIIQ36sI", blob, header_size + boff
    )
    if super_size <= 0:
        raise SystemExit("block-device table reports zero super size")
    if first * 512 < LP_METADATA_OFFSET:
        raise SystemExit("block-device table points into the liblp metadata region")
    return {
        "first_logical_sector": int(first),
        "data_start": int(first) * 512,
        "alignment": int(alignment),
        "alignment_offset": int(alignment_offset),
        "super_bytes": int(super_size),
        "name": raw_name.split(b"\0", 1)[0].decode("utf-8", "replace"),
        "flags": int(flags),
    }


def image_name_candidates(logical: str, suffix: str) -> list[str]:
    candidates = [logical]
    if suffix and logical.endswith(suffix):
        candidates.insert(0, logical[: -len(suffix)])
    return [f"{name}.img" for name in candidates]


def resolve_image(images: Path, logical: str, suffix: str) -> Path | None:
    for name in image_name_candidates(logical, suffix):
        path = images / name
        if path.is_file():
            return path
    return None


def partition_sectors(part) -> int:
    return sum(extent.num_sectors for extent in part.extents)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--images", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, default=Path("reports/super-layout.json"))
    parser.add_argument("--partition", action="append", default=[], help="base or logical partition name")
    parser.add_argument("--slot-suffix", default="_a", help="suffix used when mapping base names (default _a)")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    template = args.template
    if template.stat().st_size < LP_METADATA_OFFSET + 2 * 65536:
        raise SystemExit("template file is too small to contain liblp metadata")
    if is_sparse(template):
        raise SystemExit(
            "template is an Android sparse image; expand it first "
            "(python scripts/partition_inspect.py has no fuse mode, use simg2img or unsparse)"
        )
    block = block_device_info(template)
    geometry, metadata = read_lp_metadata(template)
    with template.open("rb") as handle:
        handle.seek(LP_METADATA_OFFSET)
        metadata_blob = handle.read(geometry["max_metadata_bytes"])
        if len(metadata_blob) != geometry["max_metadata_bytes"]:
            raise SystemExit("template metadata is truncated")
        handle.seek(0)
        prefix = handle.read(LP_METADATA_OFFSET)
    writer = SuperWriter(geometry, metadata, metadata_blob)
    requested = set(args.partition)
    cursor = align_up(max(block["data_start"], LP_METADATA_OFFSET + 2 * geometry["metadata_slots"] * geometry["max_metadata_bytes"]))
    records = []
    for part in metadata.partitions:
        logical = part.name
        base = logical[:-len(args.slot_suffix)] if args.slot_suffix and logical.endswith(args.slot_suffix) else logical
        selected = not requested or logical in requested or base in requested
        if not selected:
            records.append({"name": logical, "action": "preserved", "bytes": partition_sectors(part) * 512})
            continue
        image = resolve_image(args.images, logical, args.slot_suffix)
        if image is None:
            if partition_sectors(part) == 0:
                records.append({"name": logical, "action": "empty"})
                continue
            if requested and base not in requested and logical not in requested:
                records.append({"name": logical, "action": "preserved", "bytes": partition_sectors(part) * 512})
                continue
            raise SystemExit(f"missing image for selected partition {logical} (tried {image_name_candidates(logical, args.slot_suffix)})")
        size = image.stat().st_size
        if size == 0:
            records.append({"name": logical, "action": "empty"})
            continue
        if size % metadata.block_size:
            raise SystemExit(f"{image}: {size} bytes is not a multiple of {metadata.block_size}")
        cursor = align_up(cursor)
        writer.set_extent(part, size // 512, cursor // 512)
        records.append({
            "name": logical,
            "action": "replaced",
            "image": image.name,
            "bytes": size,
            "offset": cursor,
        })
        cursor += size
    if cursor > block["super_bytes"]:
        raise SystemExit(f"allocated {cursor:,} bytes exceeds super size {block['super_bytes']:,}")

    replaced_names = {item["name"] for item in records if item["action"] == "replaced"}
    needs_template_data = any(
        part.name not in replaced_names and partition_sectors(part) > 0
        for part in metadata.partitions
    )
    if needs_template_data and template.stat().st_size < block["super_bytes"]:
        raise SystemExit(
            "template does not contain the full partition data; "
            "pass the complete gaokun3 super image, not only its first MiB"
        )

    report = {
        "template": str(template.resolve()),
        "output": str(args.output.resolve()),
        "block_device": block,
        "geometry": geometry,
        "data_start": cursor - sum(item.get("bytes", 0) for item in records if item["action"] == "replaced"),
        "partitions": records,
    }
    if args.dry_run:
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    metadata_region = writer.to_bytes().ljust(geometry["max_metadata_bytes"], b"\0")

    # Preserve every partition that was not replaced by copying its existing
    # extents from the template. The output is a new file, so extents alone do
    # not carry any data.
    preserved = []
    for part in metadata.partitions:
        if any(item["name"] == part.name and item["action"] == "replaced" for item in records):
            continue
        for extent in part.extents:
            if extent.num_sectors:
                preserved.append({
                    "name": part.name,
                    "offset": extent.target_data * 512,
                    "bytes": extent.num_sectors * 512,
                })

    with args.output.open("wb") as out:
        out.write(prefix)
        for _ in range(geometry["metadata_slots"] * 2):
            out.write(metadata_region)
        for item in records:
            if item["action"] != "replaced":
                continue
            out.seek(item["offset"])
            image = args.images / item["image"]
            with image.open("rb") as src:
                while block_bytes := src.read(8 * ALIGN):
                    out.write(block_bytes)
        with template.open("rb") as src:
            for item in preserved:
                src.seek(item["offset"])
                out.seek(item["offset"])
                remaining = item["bytes"]
                while remaining:
                    chunk = src.read(min(8 * ALIGN, remaining))
                    if not chunk:
                        raise SystemExit(f"template ended while preserving {item['name']}")
                    out.write(chunk)
                    remaining -= len(chunk)
        out.truncate(block["super_bytes"])
    report["preserved"] = preserved
    report["output_sha256"] = hashlib.sha256(args.output.read_bytes()).hexdigest()
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"WROTE  {args.output} ({args.output.stat().st_size:,} bytes)")
    print(f"REPORT {args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
