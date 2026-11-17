#!/usr/bin/env python3
"""End-to-end synthetic OTA tests for payload inspection and extraction."""
from __future__ import annotations

import hashlib
import io
import json
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "coloros-port" / "scripts"
sys.path.insert(0, str(SCRIPTS))

from ota_inspect import parse_manifest  # noqa: E402


def varint(value: int) -> bytes:
    out = bytearray()
    while value > 0x7F:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def field(number: int, wire: int, value: bytes | int) -> bytes:
    key = varint((number << 3) | wire)
    if wire == 0:
        return key + varint(int(value))
    return key + varint(len(value)) + value


def message(**kwargs) -> bytes:
    return b"".join(value for _, value in sorted(kwargs.items()))


def extent(start: int, blocks: int) -> bytes:
    return field(1, 0, start) + field(2, 0, blocks)


def operation(kind: int, offset: int, data: bytes, blocks: int) -> bytes:
    out = field(1, 0, kind)
    out += field(2, 0, offset)
    out += field(3, 0, len(data))
    out += field(4, 2, hashlib.sha256(data).digest())
    out += field(6, 2, extent(0, blocks))
    return out


def partition(name: str, operations: list[bytes]) -> bytes:
    return field(1, 2, name.encode()) + b"".join(field(8, 2, op) for op in operations)


def build_ota(path: Path, include_metadata: bool = True) -> dict:
    block = b"X" * 4096
    zero_op = field(1, 0, 6) + field(6, 2, extent(1, 2))
    replace_op = operation(0, 0, block, 1)
    system = partition("system", [replace_op, zero_op])
    manifest = field(3, 0, 4096) + field(13, 2, system) + field(14, 0, 1)
    payload = b"CrAU" + struct.pack(">Q", 2) + struct.pack(">Q", len(manifest))
    payload += struct.pack(">I", 0) + manifest + block
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("payload.bin", payload)
        if include_metadata:
            archive.writestr("META-INF/com/android/metadata", "post-build=OPD2413\npost-timestamp=123\n")
    return {"block": block, "payload": payload}


class OtaTests(unittest.TestCase):
    def test_manifest_enum_and_extents(self):
        with tempfile.TemporaryDirectory() as temp:
            ota = Path(temp) / "ota.zip"
            build_ota(ota)
            result = subprocess.run(
                [sys.executable, str(SCRIPTS / "ota_inspect.py"), str(ota), "--report", str(Path(temp) / "r.json")],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads((Path(temp) / "r.json").read_text())
            parts = report["payload"]["partitions"]
            self.assertEqual(parts[0]["name"], "system")
            self.assertEqual(parts[0]["bytes"], 3 * 4096)

    def test_payload_extract(self):
        with tempfile.TemporaryDirectory() as temp:
            ota = Path(temp) / "ota.zip"
            expected = build_ota(ota)
            output = Path(temp) / "parts"
            result = subprocess.run(
                [sys.executable, str(SCRIPTS / "payload_extract.py"), str(ota), "--output", str(output),
                 "--report", str(Path(temp) / "r.json")],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            image = (output / "system.img").read_bytes()
            self.assertEqual(image, expected["block"] + b"\0" * 8192)


if __name__ == "__main__":
    unittest.main()
