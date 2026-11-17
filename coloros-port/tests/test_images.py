#!/usr/bin/env python3
"""Synthetic tests for sparse and liblp handling. No donor image needed."""
from __future__ import annotations

import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "coloros-port" / "scripts"))

from lib_android import LP_MAGIC, read_lp_metadata, unsparse  # noqa: E402

SPARSE_MAGIC = 0xED26FF3A


def sparse_header(blocks: int, chunks: int) -> bytes:
    return struct.pack("<IHHHHIIII", SPARSE_MAGIC, 1, 0, 28, 12, 4096, blocks, chunks, 0)


def sparse_chunk(kind: int, blocks: int, payload: bytes) -> bytes:
    return struct.pack("<HHII", kind, 0, blocks, 12 + len(payload)) + payload


def make_sparse(path: Path) -> bytes:
    data = sparse_header(4, 3)
    data += sparse_chunk(0xCAC1, 1, b"A" * 4096)
    data += sparse_chunk(0xCAC2, 1, struct.pack("<I", 0x42424242))
    data += sparse_chunk(0xCAC3, 2, b"")
    path.write_bytes(data)
    return b"A" * 4096 + b"B" * 4096 + b"\0" * 8192


def build_lp_header(table_bytes: bytes) -> bytes:
    header_size = 256
    header = bytearray(header_size)
    struct.pack_into("<IHHI", header, 0, LP_MAGIC, 10, 2, header_size)
    struct.pack_into("<I", header, 44, len(table_bytes))
    struct.pack_into("<III", header, 80, 0, 2, 52)
    struct.pack_into("<III", header, 92, 104, 2, 24)
    struct.pack_into("<III", header, 104, 152, 1, 48)
    struct.pack_into("<III", header, 116, 200, 1, 64)
    header[48:80] = hashlib.sha256(table_bytes).digest()
    header[12:44] = bytes(32)
    header[12:44] = hashlib.sha256(header).digest()
    return bytes(header)


def make_super(path: Path, metadata_size: int = 8192, first_sector: int = 0x8000) -> None:
    partitions = bytearray()
    partitions += b"system_a".ljust(36, b"\0") + struct.pack("<IIII", 0, 0, 1, 0)
    partitions += b"vendor_a".ljust(36, b"\0") + struct.pack("<IIII", 0, 1, 1, 0)
    extents = bytearray()
    extents += struct.pack("<QIQI", 8, 0, first_sector, 0)
    extents += struct.pack("<QIQI", 8, 0, first_sector + 0x2000, 0)
    groups = b"default".ljust(36, b"\0") + struct.pack("<IQ", 0, 64 * 1024 * 1024)
    block_device = struct.pack("<QIIQ36sI", first_sector, 1, 0, 64 * 1024 * 1024, b"super", 0)
    tables = bytes(partitions) + bytes(extents) + groups + block_device
    metadata = (build_lp_header(tables) + tables).ljust(metadata_size, b"\0")

    geometry = bytearray(4096)
    struct.pack_into("<I", geometry, 0, 0x616C4467)
    struct.pack_into("<III", geometry, 40, metadata_size, 2, 4096)
    seed = bytearray(geometry[:52])
    seed[8:40] = bytes(32)
    geometry[8:40] = hashlib.sha256(seed).digest()

    with path.open("wb") as out:
        out.write(bytes(4096))
        out.write(geometry)
        out.write(geometry)
        for _ in range(4):
            out.write(metadata)
        out.seek(first_sector * 512)
        out.write(b"S" * 4096)
        out.seek((first_sector + 0x2000) * 512)
        out.write(b"V" * 4096)
        out.truncate(64 * 1024 * 1024)


class ImageTests(unittest.TestCase):
    def test_sparse_expand(self):
        with tempfile.TemporaryDirectory() as temp:
            src = Path(temp) / "sparse.img"
            expected = make_sparse(src)
            dst = Path(temp) / "raw.img"
            unsparse(src, dst)
            self.assertEqual(dst.read_bytes(), expected)

    def test_super_inspect(self):
        with tempfile.TemporaryDirectory() as temp:
            image = Path(temp) / "super.img"
            make_super(image)
            geometry, metadata = read_lp_metadata(image)
            self.assertEqual(geometry["max_metadata_bytes"], 8192)
            self.assertEqual([p.name for p in metadata.partitions], ["system_a", "vendor_a"])

    def test_sparse_template_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            raw = Path(temp) / "super.img"
            make_super(raw)
            sparse = Path(temp) / "super-sparse.img"
            # Minimal valid sparse wrapper around the raw bytes is enough to
            # exercise the guard; the repacker must not try to parse it.
            payload = raw.read_bytes()
            header = struct.pack("<IHHHHIIII", 0xED26FF3A, 1, 0, 28, 12, 4096, len(payload) // 4096, 1, 0)
            sparse.write_bytes(header + struct.pack("<HHII", 0xCAC1, 0, len(payload) // 4096, 12 + len(payload)) + payload)
            result = subprocess.run(
                [sys.executable, str(ROOT / "coloros-port" / "scripts" / "super_repack.py"),
                 "--template", str(sparse), "--images", str(Path(temp)), "--output", str(Path(temp) / "out.img"),
                 "--dry-run"],
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("sparse", result.stderr.lower())

    def test_super_repack_preserves_vendor(self):
        with tempfile.TemporaryDirectory() as temp:
            template = Path(temp) / "super.img"
            make_super(template)
            parts = Path(temp) / "parts"
            parts.mkdir()
            (parts / "system.img").write_bytes(b"Z" * 8192)
            output = Path(temp) / "out.img"
            report = Path(temp) / "layout.json"
            result = subprocess.run(
                [sys.executable, str(ROOT / "coloros-port" / "scripts" / "super_repack.py"),
                 "--template", str(template), "--images", str(parts),
                 "--output", str(output), "--report", str(report),
                 "--partition", "system"],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            data = output.read_bytes()
            first, _, _, _, _, _ = struct.unpack_from("<QIIQ36sI", data, 12288 + 256 + 200)
            self.assertEqual(data[first * 512:first * 512 + 4096], b"Z" * 4096)
            vendor = first + 0x2000
            self.assertEqual(data[vendor * 512:vendor * 512 + 4096], b"V" * 4096)


if __name__ == "__main__":
    unittest.main()
