#!/usr/bin/env python3
"""Extract full-system partition images from an Android OTA payload.

Supported operations:
  REPLACE, REPLACE_BZ, REPLACE_XZ, ZERO, DISCARD

Operations that require a source image (MOVE, BSDIFF, SOURCE_COPY,
SOURCE_BSDIFF, PUFFDIFF, BROTLI_BSDIFF) are rejected rather than silently
producing a corrupt partition.

Usage:
    python scripts/payload_extract.py inputs/ota.zip --output work/parts
    python scripts/payload_extract.py inputs/ota.zip --output work/parts system product
"""
from __future__ import annotations

import argparse
import bz2
import hashlib
import json
import lzma
import struct
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from ota_inspect import parse_manifest, partition_total  # noqa: E402

SUPPORTED = {"REPLACE", "REPLACE_BZ", "REPLACE_XZ", "ZERO", "DISCARD"}


def read_exact(stream, size: int) -> bytes:
    data = bytearray()
    while len(data) < size:
        block = stream.read(size - len(data))
        if not block:
            raise ValueError("truncated payload data")
        data.extend(block)
    return bytes(data)


def write_zeros(output, size: int) -> None:
    zero = b"\0" * (1024 * 1024)
    while size:
        piece = min(len(zero), size)
        output.write(zero[:piece])
        size -= piece


def decompress_operation(stream, output, compressed: int, kind: str) -> hashlib._Hash:
    hasher = hashlib.sha256()
    decompressor = bz2.BZ2Decompressor() if kind == "REPLACE_BZ" else lzma.LZMADecompressor()
    remaining = compressed
    while remaining:
        block = stream.read(min(1024 * 1024, remaining))
        if not block:
            raise ValueError(f"truncated {kind} payload")
        remaining -= len(block)
        data = decompressor.decompress(block)
        output.write(data)
        hasher.update(data)
    if not decompressor.eof:
        raise ValueError(f"incomplete {kind} stream")
    return hasher


def operation_target_offset(op: dict) -> int:
    extents = op.get("dst_extents") or []
    if extents:
        return min(int(item.get("start_block", 0)) for item in extents) * 4096
    return 0


def extract_partition(raw, data_start: int, part: dict, output: Path) -> dict:
    name = part.get("name")
    operations = part.get("operations", [])
    unsupported = sorted({op.get("type") for op in operations if op.get("type") not in SUPPORTED})
    if unsupported:
        return {"name": name, "status": "skipped", "reason": ",".join(map(str, unsupported))}
    target_blocks = 0
    for op in operations:
        for extent in op.get("dst_extents") or []:
            end = int(extent.get("start_block", 0)) + int(extent.get("num_blocks", 0))
            target_blocks = max(target_blocks, end)
    target_size = target_blocks * 4096
    with output.open("wb") as out:
        out.truncate(target_size)
        for op in operations:
            kind = op["type"]
            compressed = int(op.get("data_length") or 0)
            digest = op.get("data_sha256_hash")
            target_offset = operation_target_offset(op)
            out.seek(target_offset)
            if kind in ("REPLACE", "REPLACE_BZ", "REPLACE_XZ"):
                raw.seek(data_start + int(op.get("data_offset") or 0))
            if kind == "REPLACE":
                hasher = hashlib.sha256()
                remaining = compressed
                while remaining:
                    block = raw.read(min(8 * 1024 * 1024, remaining))
                    if not block:
                        raise ValueError(f"{name}: truncated REPLACE payload")
                    out.write(block)
                    hasher.update(block)
                    remaining -= len(block)
                if digest and hasher.hexdigest() != digest:
                    raise ValueError(f"{name}: REPLACE SHA-256 mismatch")
            elif kind in ("REPLACE_BZ", "REPLACE_XZ"):
                hasher = decompress_operation(raw, out, compressed, kind)
                if digest and hasher.hexdigest() != digest:
                    raise ValueError(f"{name}: {kind} decompressed SHA-256 mismatch")
            else:
                write_zeros(out, partition_total({"operations": [op]}))
    final = hashlib.sha256()
    with output.open("rb") as check:
        while block := check.read(8 * 1024 * 1024):
            final.update(block)
    return {
        "name": name,
        "status": "extracted",
        "bytes": output.stat().st_size,
        "sha256": final.hexdigest(),
    }


def extract_partitions(zip_path: Path, output_dir: Path, wanted: set[str] | None) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        entry = next((item for item in archive.infolist() if Path(item.filename).name == "payload.bin"), None)
        if entry is None:
            raise SystemExit("no payload.bin in OTA zip")
        with archive.open(entry) as raw:
            header = read_exact(raw, 24)
            if header[:4] != b"CrAU":
                raise SystemExit("unexpected payload magic")
            version = struct.unpack_from(">Q", header, 4)[0]
            manifest_size = struct.unpack_from(">Q", header, 12)[0]
            signature_size = struct.unpack_from(">I", header, 20)[0]
            manifest = parse_manifest(read_exact(raw, manifest_size))
            # The metadata block is header + manifest + metadata signature.
            # Operation data_offset values are relative to the data blob area.
            data_start = 24 + manifest_size + signature_size
            results = []
            for part in manifest.get("partitions", []):
                if wanted is not None and part.get("name") not in wanted:
                    continue
                target = output_dir / f"{part.get('name')}.img"
                try:
                    results.append(extract_partition(raw, data_start, part, target))
                except ValueError as exc:
                    results.append({"name": part.get("name"), "status": "failed", "reason": str(exc)})
    return {"payload_version": version, "manifest_size": manifest_size, "partitions": results}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("partitions", nargs="*", help="optional partition names")
    parser.add_argument("--report", type=Path, default=Path("reports/payload-extract.json"))
    args = parser.parse_args(argv)
    if not args.zip.is_file():
        parser.error(f"not a file: {args.zip}")
    wanted = set(args.partitions) or None
    report = extract_partitions(args.zip, args.output, wanted)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for item in report["partitions"]:
        if item["status"] == "extracted":
            print(f"OK      {item['name']:<20} {item['bytes']:>14,} bytes  {item['sha256'][:16]}")
        else:
            print(f"{item['status'].upper():<8}{item['name']:<20} {item.get('reason', '')}")
    print(f"REPORT  {args.report}")
    return 1 if any(item["status"] != "extracted" for item in report["partitions"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
