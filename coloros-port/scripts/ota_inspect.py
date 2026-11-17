#!/usr/bin/env python3
"""Inspect a local ColorOS OTA zip without extracting or trusting it.

The tool reads the zip central directory, then parses the Android OTA
payload.bin protobuf manifest directly.  It reports partition names, sizes,
operation types and hashes, plus the metadata later stages need.

Nothing is written outside the report path.  The payload itself is streamed,
never fully extracted.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
import zipfile
from pathlib import Path
from typing import Any, Iterable

PAYLOAD_MAGIC = b"CrAU"
HEADER_BYTES = 24

# InstallOperation.Type from update_engine/update_metadata.proto
OPERATION_TYPES = {
    0: "REPLACE",
    1: "REPLACE_BZ",
    2: "MOVE",
    3: "BSDIFF",
    4: "SOURCE_COPY",
    5: "SOURCE_BSDIFF",
    6: "ZERO",
    7: "DISCARD",
    8: "REPLACE_XZ",
    9: "PUFFDIFF",
    10: "BROTLI_BSDIFF",
}


def read_varint(data: bytes, offset: int) -> tuple[int, int]:
    """Decode a protobuf base-128 varint."""
    value = 0
    shift = 0
    start = offset
    while offset < len(data):
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, offset
        shift += 7
        if shift > 70:
            raise ValueError(f"varint too long at offset {start}")
    raise ValueError(f"truncated varint at offset {start}")


def iter_fields(data: bytes) -> Iterable[tuple[int, int, Any]]:
    """Yield (field_number, wire_type, value) for a protobuf message."""
    offset = 0
    while offset < len(data):
        key, offset = read_varint(data, offset)
        number, wire = key >> 3, key & 7
        if number == 0:
            raise ValueError("invalid protobuf field number 0")
        if wire == 0:
            value, offset = read_varint(data, offset)
            yield number, wire, value
        elif wire == 1:
            if offset + 8 > len(data):
                raise ValueError("truncated fixed64 field")
            yield number, wire, data[offset:offset + 8]
            offset += 8
        elif wire == 2:
            size, offset = read_varint(data, offset)
            end = offset + size
            if end > len(data):
                raise ValueError("truncated length-delimited field")
            yield number, wire, data[offset:end]
            offset = end
        elif wire == 5:
            if offset + 4 > len(data):
                raise ValueError("truncated fixed32 field")
            yield number, wire, data[offset:offset + 4]
            offset += 4
        else:
            raise ValueError(f"unsupported protobuf wire type {wire}")


def as_text(value: Any) -> str:
    if isinstance(value, (bytes, bytearray)):
        return bytes(value).decode("utf-8", "replace")
    return str(value)


def parse_extent(data: bytes) -> dict[str, int]:
    extent = {"start_block": 0, "num_blocks": 0}
    for number, _, value in iter_fields(data):
        if number == 1:
            extent["start_block"] = int(value)
        elif number == 2:
            extent["num_blocks"] = int(value)
    return extent


def parse_operation(data: bytes) -> dict[str, Any]:
    op: dict[str, Any] = {"type": None}
    for number, wire, value in iter_fields(data):
        if number == 1:
            op["type"] = OPERATION_TYPES.get(int(value), f"UNKNOWN_{int(value)}")
        elif number == 2:
            op["data_offset"] = int(value)
        elif number == 3:
            op["data_length"] = int(value)
        elif number == 4 and wire == 2:
            op["data_sha256_hash"] = bytes(value).hex()
        elif number == 5 and wire == 2:
            op.setdefault("src_extents", []).append(parse_extent(value))
        elif number == 6 and wire == 2:
            op.setdefault("dst_extents", []).append(parse_extent(value))
        elif number == 7 and wire == 2:
            op["src_sha256_hash"] = bytes(value).hex()
        elif number == 8 and wire == 2:
            op["dst_sha256_hash"] = bytes(value).hex()
    return op


def looks_like_operation(data: bytes) -> bool:
    try:
        numbers = {number for number, _, _ in iter_fields(data)}
        return 1 in numbers and 2 in numbers and 3 in numbers
    except ValueError:
        return False


def parse_partition(data: bytes) -> dict[str, Any]:
    part: dict[str, Any] = {"name": None, "operations": []}
    for number, wire, value in iter_fields(data):
        if number == 1:
            part["name"] = as_text(value)
        elif number == 8 and wire == 2:
            # OPlus ColorOS payload uses field 8 for InstallOperation.
            part["operations"].append(parse_operation(value))
        elif number == 2 and wire == 2 and looks_like_operation(value):
            # Keep compatibility with standard payloads.
            part["operations"].append(parse_operation(value))
        elif number == 4:
            part["filesystem_type"] = as_text(value)
    return part


def looks_like_partition(data: bytes) -> bool:
    try:
        for number, wire, value in iter_fields(data):
            if number == 1 and wire == 2:
                name = as_text(value)
                return bool(name) and all(32 <= ord(char) < 127 for char in name)
    except ValueError:
        return False
    return False


def parse_manifest(data: bytes) -> dict[str, Any]:
    """Parse AOSP and OPlus ColorOS payload manifests.

    Standard update_engine stores partitions in field 1. OPlus ColorOS 17 puts
    them in repeated field 13 and uses field 3 for block size. We accept both
    layouts and reject non-partition field 13 messages.
    """
    manifest: dict[str, Any] = {"partitions": [], "block_size": None}
    for number, wire, value in iter_fields(data):
        if number == 1 and wire == 2:
            manifest["partitions"].append(parse_partition(value))
        elif number == 13 and wire == 2 and looks_like_partition(value):
            manifest["partitions"].append(parse_partition(value))
        elif number in (2, 3):
            field = "block_size" if number == 3 else "max_timestamp"
            manifest[field] = int(value)
        elif number == 4:
            manifest["data_blob_size"] = int(value)
        elif number == 5:
            manifest["metadata_signature_size"] = int(value)
        elif number == 12:
            manifest["minor_version"] = int(value)
        elif number == 14:
            manifest["max_timestamp"] = int(value)
        elif number == 16:
            manifest["partial_update"] = bool(int(value))
    return manifest


def sha256_file(path: Path, chunk: int = 8 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(chunk):
            digest.update(block)
    return digest.hexdigest()


def read_payload_header(stream) -> dict[str, Any]:
    header = stream.read(HEADER_BYTES)
    if len(header) != HEADER_BYTES:
        raise ValueError("payload header is truncated")
    magic = header[:4]
    if magic != PAYLOAD_MAGIC:
        raise ValueError(f"unexpected payload magic {magic!r}")
    # update_engine payload headers are network byte order (big endian).
    version = struct.unpack_from(">Q", header, 4)[0]
    manifest_size = struct.unpack_from(">Q", header, 12)[0]
    metadata_signature_size = struct.unpack_from(">I", header, 20)[0]
    if manifest_size == 0 or manifest_size > 64 * 1024 * 1024:
        raise ValueError(f"implausible manifest size {manifest_size}")
    return {
        "magic": magic.decode("ascii"),
        "version": version,
        "manifest_size": manifest_size,
        "metadata_signature_size": metadata_signature_size,
    }


def partition_total(part: dict[str, Any]) -> int:
    total = 0
    for op in part.get("operations", []):
        extents = op.get("dst_extents") or []
        if extents:
            total += sum(int(extent.get("num_blocks", 0)) for extent in extents) * 4096
        else:
            total += int(op.get("data_length") or 0)
    return total


def inspect_zip(path: Path, hash_zip: bool) -> dict[str, Any]:
    report: dict[str, Any] = {
        "path": str(path.resolve()),
        "bytes": path.stat().st_size,
        "sha256": sha256_file(path) if hash_zip else None,
        "entries": [],
        "payload": None,
        "problems": [],
    }
    try:
        with zipfile.ZipFile(path) as archive:
            report["entries"] = [
                {"name": item.filename, "size": item.file_size, "compressed": item.compress_size}
                for item in archive.infolist()
            ]
            names = {item.filename for item in archive.infolist()}
            metadata_entry = next((n for n in names if n.upper() == "META-INF/COM/ANDROID/METADATA"), None)
            if metadata_entry:
                raw_metadata = archive.read(metadata_entry).decode("utf-8", "replace")
                parsed = {}
                for line in raw_metadata.splitlines():
                    if "=" in line:
                        key, value = line.split("=", 1)
                        parsed[key.strip()] = value.strip()
                report["ota_metadata"] = parsed
            candidates = [n for n in names if Path(n).name == "payload.bin"]
            if not candidates:
                report["problems"].append("no payload.bin entry: not an Android OTA payload zip")
                return report
            entry = archive.getinfo(candidates[0])
            with archive.open(entry) as stream:
                header = read_payload_header(stream)
                raw_manifest = stream.read(header["manifest_size"])
            if len(raw_manifest) != header["manifest_size"]:
                raise ValueError("payload manifest is truncated")
            manifest = parse_manifest(raw_manifest)
            header["entry"] = entry.filename
            header["compressed_size"] = entry.compress_size
            header["uncompressed_size"] = entry.file_size
            header["partitions"] = [
                {"name": part["name"], "bytes": partition_total(part), "operations": len(part["operations"])}
                for part in manifest.get("partitions", [])
            ]
            header["block_size"] = manifest.get("block_size")
            header["partition_count"] = len(manifest.get("partitions", []))
            header["full_manifest"] = manifest
            report["payload"] = header
    except (OSError, zipfile.BadZipFile, ValueError) as exc:
        report["problems"].append(f"{type(exc).__name__}: {exc}")
    return report


def summarize(report: dict[str, Any]) -> None:
    print(f"FILE    {report['path']}")
    print(f"SIZE    {report['bytes']:,} bytes")
    if report.get("sha256"):
        print(f"SHA256  {report['sha256']}")
    payload = report.get("payload")
    if not payload:
        print("PAYLOAD missing")
    else:
        print(f"PAYLOAD {payload['entry']} ({payload['uncompressed_size']:,} bytes, v{payload['version']})")
        print(f"BLOCK   {payload.get('block_size')}")
        print(f"PARTS   {payload['partition_count']}")
        for part in payload["partitions"]:
            print(f"  {part['name'] or '?':<18} {part['bytes']:>14,} bytes  {part['operations']} ops")
    for problem in report.get("problems", []):
        print(f"PROBLEM {problem}", file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("zip", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--hash", action="store_true", help="also hash the whole OTA zip")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    if not args.zip.is_file():
        parser.error(f"not a file: {args.zip}")
    report = inspect_zip(args.zip, args.hash)
    if not args.quiet:
        summarize(report)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        report.pop("full_manifest", None)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return 1 if report["problems"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
