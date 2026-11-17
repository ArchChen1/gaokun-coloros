"""Shared helpers: Android sparse images and liblp super metadata."""
from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import BinaryIO, Iterator

SPARSE_MAGIC = 0xED26FF3A
SPARSE_HEADER = 28
SPARSE_CHUNK = 12
CHUNK_TYPES = {
    0xCAC1: "raw",
    0xCAC2: "fill",
    0xCAC3: "don't care",
    0xCAC4: "crc32",
}
LP_MAGIC = 0x414C5030
LP_GEOMETRY_MAGIC = 0x616C4467
LP_METADATA_OFFSET = 4096 * 3


def sha256_file(path: Path, chunk: int = 8 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(chunk):
            digest.update(block)
    return digest.hexdigest()


def is_sparse(path: Path) -> bool:
    with path.open("rb") as handle:
        return struct.unpack("<I", handle.read(4))[0] == SPARSE_MAGIC


@dataclass
class SparseHeader:
    major: int
    minor: int
    file_header_size: int
    chunk_header_size: int
    block_size: int
    total_blocks: int
    total_chunks: int
    checksum: int

    @property
    def output_bytes(self) -> int:
        return self.total_blocks * self.block_size


def read_sparse_header(handle: BinaryIO) -> SparseHeader:
    raw = handle.read(SPARSE_HEADER)
    if len(raw) != SPARSE_HEADER:
        raise ValueError("truncated sparse header")
    values = struct.unpack("<IHHHHIIII", raw)
    if values[0] != SPARSE_MAGIC:
        raise ValueError("not an Android sparse image")
    return SparseHeader(*values[1:])


def iter_sparse_chunks(handle: BinaryIO, header: SparseHeader | None = None) -> Iterator[dict]:
    """Yield sparse chunks and leave the cursor at each chunk's payload.

    The consumer must consume or seek past the payload.  Unsparse does so
    explicitly.  Metadata-only callers can call skip_sparse_payload().
    """
    if header is None:
        header = read_sparse_header(handle)
    if header.major != 1:
        raise ValueError(f"unsupported sparse major version {header.major}")
    for index in range(header.total_chunks):
        raw = handle.read(SPARSE_CHUNK)
        if len(raw) != SPARSE_CHUNK:
            raise ValueError("truncated sparse chunk header")
        kind, _reserved, blocks, total = struct.unpack("<HHII", raw)
        payload_size = total - SPARSE_CHUNK
        if payload_size < 0:
            raise ValueError("invalid sparse chunk size")
        name = CHUNK_TYPES.get(kind, f"unknown(0x{kind:04x})")
        yield {
            "index": index,
            "kind": kind,
            "kind_name": name,
            "blocks": blocks,
            "payload_bytes": payload_size,
            "handle": handle,
            "header": header,
        }


def skip_sparse_payload(chunk: dict) -> None:
    chunk["handle"].seek(chunk["payload_bytes"], 1)


def unsparse(source: Path, target: Path) -> dict:
    """Expand an Android sparse image to a raw image."""
    with source.open("rb") as inp:
        chunks = 0
        written = 0
        header = None
        with target.open("wb") as out:
            for chunk in iter_sparse_chunks(inp):
                header = chunk["header"]
                chunks += 1
                payload = chunk["payload_bytes"]
                if chunk["kind"] in (0xCAC1, 0xCAC4):
                    remaining = payload
                    while remaining:
                        block = inp.read(min(8 * 1024 * 1024, remaining))
                        if not block:
                            raise ValueError("truncated sparse payload")
                        out.write(block)
                        remaining -= len(block)
                        written += len(block)
                elif chunk["kind"] == 0xCAC2:
                    if payload != 4:
                        raise ValueError("invalid fill chunk payload")
                    value = inp.read(4)
                    if len(value) != 4:
                        raise ValueError("truncated fill chunk")
                    for _ in range(chunk["blocks"]):
                        out.write(value * (header.block_size // 4))
                    written += chunk["blocks"] * header.block_size
                elif chunk["kind"] == 0xCAC3:
                    zeros = b"\0" * 1024 * 1024
                    remaining = chunk["blocks"] * header.block_size
                    while remaining:
                        piece = min(len(zeros), remaining)
                        out.write(zeros[:piece])
                        remaining -= piece
                    written += chunk["blocks"] * header.block_size
                    inp.seek(payload, 1)
                else:
                    raise ValueError(f"unsupported chunk type 0x{chunk['kind']:04x}")
        if header is None:
            raise ValueError("sparse image has no chunks")
        expected = header.output_bytes
        if written != expected:
            raise ValueError(f"sparse expansion wrote {written}, expected {expected}")
        return {
            "source": str(source),
            "raw": str(target),
            "block_size": header.block_size,
            "total_blocks": header.total_blocks,
            "chunks": chunks,
            "raw_bytes": expected,
        }


def describe_sparse(path: Path) -> dict:
    with path.open("rb") as handle:
        header = read_sparse_header(handle)
        counts: dict[str, int] = {}
        for chunk in iter_sparse_chunks(handle, header):
            counts[chunk["kind_name"]] = counts.get(chunk["kind_name"], 0) + 1
            skip_sparse_payload(chunk)
    return {
        "sparse": True,
        "major": header.major,
        "minor": header.minor,
        "block_size": header.block_size,
        "total_blocks": header.total_blocks,
        "total_chunks": header.total_chunks,
        "raw_bytes": header.output_bytes,
        "chunk_kinds": counts,
    }
def describe_sparse(path: Path) -> dict:
    with path.open("rb") as handle:
        header = read_sparse_header(handle)
        counts: dict[str, int] = {}
        for chunk in iter_sparse_chunks(handle):
            counts[chunk["kind_name"]] = counts.get(chunk["kind_name"], 0) + 1
    return {
        "sparse": True,
        "major": header.major,
        "minor": header.minor,
        "block_size": header.block_size,
        "total_blocks": header.total_blocks,
        "total_chunks": header.total_chunks,
        "raw_bytes": header.output_bytes,
        "chunk_kinds": counts,
    }


def describe_raw(path: Path) -> dict:
    return {"sparse": False, "raw_bytes": path.stat().st_size}


# --------------------------------------------------------------------------
# liblp (super.img / dynamic partitions)
# --------------------------------------------------------------------------

@dataclass
class LpExtent:
    num_sectors: int
    target_type: int
    target_data: int
    target_source: int


@dataclass
class LpPartition:
    name: str
    attributes: int
    first_extent_index: int
    num_extents: int
    group_index: int
    extents: list[LpExtent] = field(default_factory=list)


@dataclass
class LpGroup:
    name: str
    flags: int
    maximum_size: int


@dataclass
class LpMetadata:
    major: int
    minor: int
    header_size: int
    header_flags: int
    block_size: int
    partitions: list[LpPartition]
    groups: list[LpGroup]
    slot: int
    slot_offset: int

    def partition(self, name: str) -> LpPartition | None:
        return next((item for item in self.partitions if item.name == name), None)


def _lp_checksum_ok(header: bytes) -> bool:
    stored = header[12:44]
    copy = bytearray(header)
    copy[12:44] = bytes(32)
    return hashlib.sha256(bytes(copy)).digest() == stored



def parse_lp_table(blob: bytes, slot: int, slot_offset: int) -> LpMetadata:
    magic, major, minor, header_size = struct.unpack_from("<IHHI", blob, 0)
    if magic != LP_MAGIC:
        raise ValueError(f"invalid liblp magic 0x{magic:08x}")
    if not _lp_checksum_ok(blob[:header_size]):
        raise ValueError("liblp header checksum mismatch")
    # liblp header layout: tables_size is at offset 44, followed by
    # tables_checksum at 48..80 and the four table descriptors at 80..128.
    table_size = struct.unpack_from("<I", blob, 44)[0]
    tables = blob[header_size:header_size + table_size]
    # tables checksum is in the header, right after tables_size.
    if hashlib.sha256(tables).digest() != blob[48:80]:
        raise ValueError("liblp table checksum mismatch")
    # The four table descriptors live at fixed offsets in the header:
    # partitions at 80, extents at 92, groups at 104, block devices at 116.
    descriptors = [struct.unpack_from("<III", blob, 80 + index * 12) for index in range(4)]
    poff, pcount, psize = descriptors[0]
    eoff, ecount, esize = descriptors[1]
    goff, gcount, gsize = descriptors[2]
    if psize != 52 or esize != 24 or gsize != 48:
        raise ValueError(f"unexpected liblp entry sizes {psize}/{esize}/{gsize}")
    extents = []
    for index in range(ecount):
        extents.append(LpExtent(*struct.unpack_from("<QIQI", tables, eoff + index * esize)))
    partitions = []
    for index in range(pcount):
        raw_name, attributes, first, count, group = struct.unpack_from("<36sIIII", tables, poff + index * psize)
        name = raw_name.split(b"\0", 1)[0].decode("utf-8", "replace")
        item = LpPartition(name, attributes, first, count, group)
        item.extents = [extents[i] for i in range(first, first + count)]
        partitions.append(item)
    groups = []
    for index in range(gcount):
        raw_name, flags, maximum = struct.unpack_from("<36sIQ", tables, goff + index * gsize)
        groups.append(LpGroup(raw_name.split(b"\0", 1)[0].decode("utf-8", "replace"), flags, maximum))
    header_flags = struct.unpack_from("<I", blob, 128)[0] if header_size >= 132 else 0
    # liblp does not store the logical block size in the header; logical
    # partitions on this device are 4096-byte aligned.
    return LpMetadata(major, minor, header_size, header_flags, 4096, partitions, groups, slot, slot_offset)


def read_lp_metadata(path: Path) -> tuple[dict, LpMetadata]:
    with path.open("rb") as handle:
        handle.seek(4096)
        geometry = handle.read(4096)
        if len(geometry) != 4096:
            raise ValueError("super geometry is truncated")
        if struct.unpack_from("<I", geometry)[0] != LP_GEOMETRY_MAGIC:
            raise ValueError("super geometry magic mismatch")
        expected = geometry[8:40]
        geometry_check = bytearray(geometry[:52])
        geometry_check[8:40] = bytes(32)
        if hashlib.sha256(bytes(geometry_check)).digest() != expected:
            raise ValueError("super geometry checksum mismatch")
        max_size, slots, block_size = struct.unpack_from("<III", geometry, 40)
        handle.seek(LP_METADATA_OFFSET)
        found = None
        for slot in range(slots):
            offset = LP_METADATA_OFFSET + slot * max_size
            handle.seek(offset)
            blob = handle.read(max_size)
            if len(blob) < 4096:
                continue
            try:
                found = parse_lp_table(blob, slot, offset)
                break
            except ValueError:
                continue
        if found is None:
            raise ValueError("no valid liblp metadata slot found")
    geometry_info = {
        "max_metadata_bytes": max_size,
        "metadata_slots": slots,
        "block_size": block_size,
    }
    return geometry_info, found


class SuperWriter:
    """Rewrite extents for selected partitions, preserving geometry."""

    def __init__(self, geometry: dict, metadata: LpMetadata, blob: bytes):
        self.geometry = geometry
        self.metadata = metadata
        self.blob = bytearray(blob)
        self.header_size = metadata.header_size
        self.table_size = struct.unpack_from("<I", self.blob, 44)[0]
        self.descriptors = [struct.unpack_from("<III", self.blob, 80 + i * 12) for i in range(4)]

    def set_extent(self, partition: LpPartition, num_sectors: int, target_data: int) -> None:
        eoff, _ecount, esize = self.descriptors[1]
        if partition.num_extents != 1:
            raise ValueError(f"{partition.name}: expected one extent, got {partition.num_extents}")
        index = partition.first_extent_index
        # Descriptor offsets are relative to the tables area, not the metadata
        # blob (which begins with the 256-byte header).
        struct.pack_into("<QIQI", self.blob, self.header_size + eoff + index * esize, num_sectors, 0, target_data, 0)

    def to_bytes(self) -> bytes:
        header = bytearray(self.blob[:self.header_size])
        header[12:44] = bytes(32)
        tables = self.blob[self.header_size:self.header_size + self.table_size]
        header[48:80] = hashlib.sha256(bytes(tables)).digest()
        header[12:44] = hashlib.sha256(bytes(header)).digest()
        return bytes(header) + bytes(tables)


def detect_filesystem(path: Path) -> str:
    """Identify common Android read-only filesystem images."""
    with path.open("rb") as handle:
        head = handle.read(4096)
        handle.seek(1024)
        sb = handle.read(1024)
    if len(head) >= 4 and struct.unpack_from("<I", head, 1024 if len(head) > 1028 else 0)[0] == 0xE0F5E1E2:
        return "erofs"
    if len(sb) >= 58 and struct.unpack_from("<H", sb, 56)[0] == 0xEF53:
        return "ext4"
    if len(head) >= 4 and struct.unpack_from("<I", head, 0)[0] == 0x58465342:
        return "xfs"
    if len(head) >= 4 and head[:4] == b"hsqs":
        return "squashfs"
    return "unknown"


def _lp_entry_offsets(blob: bytes, header_size: int) -> dict[str, tuple[int, int]]:
    descriptors = [struct.unpack_from("<III", blob, 80 + i * 12) for i in range(4)]
    names = ("partitions", "extents", "groups", "block_devices")
    return {name: (off, size) for name, (off, _count, size) in zip(names, descriptors)}


def _lp_set_descriptor(blob: bytearray, index: int, offset: int, count: int, size: int) -> None:
    struct.pack_into("<III", blob, 80 + index * 12, offset, count, size)


def _lp_rewrite_header(blob: bytearray, tables: bytes) -> None:
    header_size = struct.unpack_from("<I", blob, 8)[0]
    struct.pack_into("<I", blob, 44, len(tables))
    blob[48:80] = hashlib.sha256(tables).digest()
    blob[12:44] = bytes(32)
    blob[12:44] = hashlib.sha256(bytes(blob[:header_size])).digest()


def append_partition(blob: bytearray, name: str, group_index: int, num_sectors: int, target_sector: int) -> int:
    """Append a logical partition to a liblp metadata slot.

    Returns the number of bytes added to the tables area. Existing entries are
    rebuilt in canonical order: partitions, extents, groups, block devices.
    """
    header_size = struct.unpack_from("<I", blob, 8)[0]
    offsets = _lp_entry_offsets(blob, header_size)
    tad = header_size
    part_off, part_size = offsets["partitions"]
    ext_off, ext_size = offsets["extents"]
    grp_off, grp_size = offsets["groups"]
    blk_off, blk_size = offsets["block_devices"]
    descriptors = [struct.unpack_from("<III", blob, 80 + i * 12) for i in range(4)]
    poff, pcount, psize = descriptors[0]
    eoff, ecount, esize = descriptors[1]
    goff, gcount, gsize = descriptors[2]
    boff, bcount, bsize = descriptors[3]
    table_size = struct.unpack_from("<I", blob, 44)[0]
    tables = bytearray(blob[tad:tad + table_size])
    partitions = [bytes(tables[poff + i * psize:poff + (i + 1) * psize]) for i in range(pcount)]
    extents = [bytes(tables[eoff + i * esize:eoff + (i + 1) * esize]) for i in range(ecount)]
    groups = [bytes(tables[goff + i * gsize:goff + (i + 1) * gsize]) for i in range(gcount)]
    blocks = [bytes(tables[boff + i * bsize:boff + (i + 1) * bsize]) for i in range(bcount)]
    # Append one extent first.
    extents.append(struct.pack("<QIQI", num_sectors, 0, target_sector, 0))
    # Partition entry references the new extent.
    raw_name = name.encode()[:35].ljust(36, b"\0")
    partitions.append(raw_name + struct.pack("<IIII", 0, len(extents) - 1, 1, group_index))
    new_part_off = 0
    new_ext_off = len(partitions) * 52
    new_grp_off = new_ext_off + len(extents) * 24
    new_blk_off = new_grp_off + len(groups) * 48
    new = b"".join(partitions) + b"".join(extents) + b"".join(groups) + b"".join(blocks)
    # The blob contains header then tables, padded to max metadata size.
    max_metadata = len(blob)
    if header_size + len(new) > max_metadata:
        raise ValueError("liblp metadata has no room for another partition")
    blob[tad:tad + len(new)] = new
    blob[tad + len(new):] = b"\0" * (max_metadata - tad - len(new))
    _lp_set_descriptor(blob, 0, new_part_off, len(partitions), 52)
    _lp_set_descriptor(blob, 1, new_ext_off, len(extents), 24)
    _lp_set_descriptor(blob, 2, new_grp_off, len(groups), 48)
    _lp_set_descriptor(blob, 3, new_blk_off, len(blocks), 64)
    _lp_rewrite_header(blob, new)
    return len(new) - table_size
