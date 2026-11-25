#!/usr/bin/env python3
"""liblp metav10：解析 / 生成带 A/B 双槽的 super 元数据（按本机实际布局）。

本机实测布局：
  4096   geometry 副本 1
  8192   geometry 副本 2（内容相同，SHA256 校验通过）
  12288  metadata 副本 1
  77824  metadata 副本 2  (12288 + 1*65536)
  143360 metadata 副本 3
  208896 metadata 副本 4
  尾部无备份元数据

元数据结构（实测）：
  header: magic(4) major(2) minor(2) header_size(4) checksum[32] tables_size(4)
          tables_checksum[32] partitions(off,num,size=12) extents groups block_devices flags(4)
  header_size = 256，checksum / tables_checksum 均为 SHA256
  表格起点 = metadata 起点 + header_size；表内 offset 相对该起点
  条目大小：partition 52 / extent 24 / group 48 / block_device 64

子命令：
  parse <head.bin>              解析 + 三重校验
  build <head.bin> <out.bin>    生成 A/B 双槽版（A 槽 extents 原样保留，B 槽放进空闲区）
"""
import hashlib
import json
import struct
import sys

GEOM_OFFS = (4096, 8192)
META_OFFS = (12288, 77824, 143360, 208896)
GEOM_MAGIC = 0x616C4467
HDR_MAGIC = 0x414C5030
GEOM_FMT = "<II32sIII"
GEOM_SIZE = struct.calcsize(GEOM_FMT)
HDR_BASE_FMT = "<IHHI32sI32s"
HDR_BASE = struct.calcsize(HDR_BASE_FMT)
DESC_SIZE = 12
HEAD_BYTES = 1048576
PART_ENTRY = 52
EXT_ENTRY = 24
GROUP_ENTRY = 48
BDEV_ENTRY = 64


def parse_geometry(d, off):
    g = d[off:off + GEOM_SIZE]
    magic, struct_size, checksum, mmax, slots, lbs = struct.unpack(GEOM_FMT, g)
    assert magic == GEOM_MAGIC, "geometry magic @%d" % off
    zeroed = g[:8] + b"\x00" * 32 + g[40:]
    return dict(raw=g, struct_size=struct_size, metadata_max_size=mmax,
                slot_count=slots, logical_block_size=lbs,
                checksum_ok=hashlib.sha256(zeroed).digest() == checksum)


def parse_meta(d, off):
    magic, major, minor, hsize, hchk, tsize, tchk = struct.unpack_from(HDR_BASE_FMT, d, off)
    if magic != HDR_MAGIC:
        return None
    descs = [struct.unpack_from("<III", d, off + HDR_BASE + i * DESC_SIZE) for i in range(4)]
    flags = struct.unpack_from("<I", d, off + HDR_BASE + 4 * DESC_SIZE)[0]
    h = bytearray(d[off:off + hsize])
    h[12:44] = b"\x00" * 32
    hdr_ok = hashlib.sha256(bytes(h)).digest() == hchk
    tstart = off + hsize
    tbl_ok = hashlib.sha256(d[tstart:tstart + tsize]).digest() == tchk
    return dict(off=off, major=major, minor=minor, header_size=hsize, tables_size=tsize,
                descs=descs, flags=flags, header_crc_ok=hdr_ok, tables_crc_ok=tbl_ok,
                template=d[off:off + hsize])


def read_tables(d, meta):
    parts, exts, groups, bdevs = [], [], [], []
    tbase = meta["off"] + meta["header_size"]
    for i, (doff, dnum, dsz) in enumerate(meta["descs"]):
        for n in range(dnum):
            e = d[tbase + doff + n * dsz: tbase + doff + (n + 1) * dsz]
            if i == 0:
                parts.append(dict(name=e[:36].split(b"\x00")[0].decode(), raw=e,
                                  attributes=struct.unpack_from("<I", e, 36)[0],
                                  first_extent=struct.unpack_from("<I", e, 40)[0],
                                  num_extents=struct.unpack_from("<I", e, 44)[0],
                                  group_index=struct.unpack_from("<I", e, 48)[0]))
            elif i == 1:
                ns, tt, td, ts = struct.unpack_from("<QIQI", e, 0)
                exts.append(dict(num_sectors=ns, target_type=tt, target_data=td,
                                 target_source=ts, raw=e))
            elif i == 2:
                groups.append(dict(name=e[:36].split(b"\x00")[0].decode(), raw=e,
                                   flags=struct.unpack_from("<I", e, 36)[0],
                                   maximum_size=struct.unpack_from("<Q", e, 40)[0]))
            else:
                fl, al, ao, sz = struct.unpack_from("<QIIQ", e, 0)
                bdevs.append(dict(name=e[24:60].split(b"\x00")[0].decode(), raw=e,
                                  first_logical_sector=fl, alignment=al,
                                  alignment_offset=ao, size=sz,
                                  flags=struct.unpack_from("<I", e, 60)[0]))
    return parts, exts, groups, bdevs


def load(path):
    d = open(path, "rb").read()
    geom = parse_geometry(d, GEOM_OFFS[0])
    meta = parse_meta(d, META_OFFS[0])
    assert meta, "metadata magic 不对"
    parts, exts, groups, bdevs = read_tables(d, meta)
    return d, geom, meta, parts, exts, groups, bdevs


def cmd_parse(path):
    d, geom, meta, parts, exts, groups, bdevs = load(path)
    info = dict(
        geometry=dict(metadata_max_size=geom["metadata_max_size"], slot_count=geom["slot_count"],
                      logical_block_size=geom["logical_block_size"],
                      checksum_ok=geom["checksum_ok"]),
        header=dict(version="%d.%d" % (meta["major"], meta["minor"]),
                    header_size=meta["header_size"], tables_size=meta["tables_size"],
                    flags=meta["flags"], virtual_ab=bool(meta["flags"] & 1),
                    header_sha_ok=meta["header_crc_ok"], tables_sha_ok=meta["tables_crc_ok"]),
        groups=[dict(name=g["name"], maximum_size=g["maximum_size"]) for g in groups],
        block_devices=[dict(name=b["name"], size=b["size"], alignment=b["alignment"],
                            first_logical_sector=b["first_logical_sector"]) for b in bdevs],
        partitions=[dict(name=p["name"], attr=p["attributes"],
                         sector=exts[p["first_extent"]]["target_data"],
                         size_sectors=sum(e["num_sectors"] for e in
                                          exts[p["first_extent"]:p["first_extent"] + p["num_extents"]]))
                    for p in parts])
    print(json.dumps(info, indent=2, ensure_ascii=False))


def align_up(x, a):
    return (x + a - 1) // a * a


def cmd_build(src, dst):
    d, geom, meta, parts, exts, groups, bdevs = load(src)
    assert geom["checksum_ok"], "geometry 校验失败"
    assert meta["header_crc_ok"] and meta["tables_crc_ok"], "元数据校验失败"

    bdev = bdevs[0]
    align_sectors = (bdev["alignment"] or 1048576) // 512
    dev_sectors = bdev["size"] // 512

    max_end = max(e["target_data"] + e["num_sectors"] for e in exts)
    start = align_up(max_end, align_sectors)

    a_parts = [p for p in parts if p["name"].endswith("_a")]
    if len(a_parts) != 13:
        raise SystemExit("A 槽分区数不是 13：%d" % len(a_parts))

    group_name = "gaokun3_dynamic_partitions_b"
    gidx = len(groups)

    new_parts, new_exts, alloc = [], [], []
    cursor = start
    for p in a_parts:
        a_exts = exts[p["first_extent"]:p["first_extent"] + p["num_extents"]]
        total = sum(e["num_sectors"] for e in a_exts)
        cursor = align_up(cursor, align_sectors)
        bname = p["name"][:-2] + "_b"
        eidx = len(exts) + len(new_exts)
        new_exts.append(struct.pack("<QIQI", total, 0, cursor, 0))
        new_parts.append(struct.pack("<36sIIII", bname.encode().ljust(36, b"\x00"),
                                     p["attributes"], eidx, 1, gidx))
        alloc.append((bname, cursor, total))
        cursor += total

    end_used = align_up(cursor, align_sectors)
    if end_used > dev_sectors:
        raise SystemExit("空间不足：需要 %d 扇区，设备 %d" % (end_used, dev_sectors))

    p_tbl = b"".join(x["raw"] for x in parts) + b"".join(new_parts)
    e_tbl = b"".join(x["raw"] for x in exts) + b"".join(new_exts)
    g_tbl = b"".join(x["raw"] for x in groups) + struct.pack(
        "<36sIQ", group_name.encode().ljust(36, b"\x00"), 0, 0)
    b_tbl = b"".join(x["raw"] for x in bdevs)
    tables = p_tbl + e_tbl + g_tbl + b_tbl

    hdr = bytearray(meta["template"])
    struct.pack_into("<I", hdr, 44, len(tables))
    for i, (off, num, sz) in enumerate([
            (0, len(parts) + len(new_parts), PART_ENTRY),
            (len(p_tbl), len(exts) + len(new_exts), EXT_ENTRY),
            (len(p_tbl) + len(e_tbl), len(groups) + 1, GROUP_ENTRY),
            (len(p_tbl) + len(e_tbl) + len(g_tbl), len(bdevs), BDEV_ENTRY)]):
        struct.pack_into("<III", hdr, HDR_BASE + i * DESC_SIZE, off, num, sz)
    struct.pack_into("<I", hdr, HDR_BASE + 4 * DESC_SIZE, meta["flags"] & ~1)
    struct.pack_into("<32s", hdr, 48, hashlib.sha256(tables).digest())
    hdr[12:44] = b"\x00" * 32
    struct.pack_into("<32s", hdr, 12, hashlib.sha256(bytes(hdr)).digest())

    blob = bytes(hdr) + tables
    if len(blob) > geom["metadata_max_size"]:
        raise SystemExit("元数据 %d 超过上限 %d" % (len(blob), geom["metadata_max_size"]))

    out = bytearray(HEAD_BYTES)
    for go in GEOM_OFFS:
        out[go:go + GEOM_SIZE] = geom["raw"]
    for mo in META_OFFS:
        out[mo:mo + len(blob)] = blob
    open(dst, "wb").write(bytes(out))

    print("B 槽分配（A 槽 extents 保持原样）：")
    for name, sec, n in alloc:
        print("  %-20s sector %10d %9d sectors %7.1f MiB" % (name, sec, n, n * 512 / 1048576))
    print("空闲起点 %d / B 槽末尾 %d / 设备末尾 %d 扇区" % (start, end_used, dev_sectors))
    print("元数据 %d 字节（上限 %d），flags 0x%x -> 0x%x" %
          (len(blob), geom["metadata_max_size"], meta["flags"], meta["flags"] & ~1))


if __name__ == "__main__":
    if len(sys.argv) < 3:
        raise SystemExit("usage: parse <head.bin> | build <head.bin> <out.bin>")
    if sys.argv[1] == "parse":
        cmd_parse(sys.argv[2])
    elif sys.argv[1] == "build":
        if len(sys.argv) < 4:
            raise SystemExit("usage: build <head.bin> <out.bin>")
        cmd_build(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit("未知子命令")
