#!/usr/bin/env python3
"""EGO 安装包（installer release）打样与自检工具。

用途：把「一个 boot.img + 一个 super 镜像」整理成上游安装器认识的发布目录，并在上机前
先把上游安装器会做的检查全部做一遍（省得到界面上才报错）。

发布目录约定（与上游 installer/backend/src/linux/apply.c 一致）：
    boot.img                  必选，Android boot image v2，带 dtb，≤ 64 MiB
    super.img.zst 或 super.img  必选，sparse 格式；zst 可选（本项目默认用未压缩的 sparse）
    install-artifacts.sha256  可选但强烈建议，两行：<sha256>  <文件名>

用法：
    python make_release.py --boot path/to/boot.img --super path/to/super.img --out out/release
    python make_release.py --boot path/to/boot.img --check-only          # 只体检 boot.img
"""

import argparse
import hashlib
import struct
import sys

SUPER_MIB = 20480            # 与 installer/backend/src/plan.h 的 GK3W_SUPER_MIB 一致
SPARSE_MAGIC = 0xED26FF3A
BOOT_MAGIC = b"ANDROID!"
FDT_MAGIC = b"\xd0\x0d\xfe\xed"


def le32(b, off):
    return struct.unpack_from("<I", b, off)[0]


def check_boot(data):
    errs = []
    if len(data) < 1660:
        return ["boot.img 太短"]
    if data[:8] != BOOT_MAGIC:
        return ["magic 不是 ANDROID!"]
    page = le32(data, 36)
    ver = le32(data, 40)
    hdr_size = le32(data, 1644)
    ksize = le32(data, 8)
    rsize = le32(data, 16)
    ssize = le32(data, 24)
    dsize = le32(data, 1648)
    if ver != 2:
        errs.append(f"header_version={ver}，安装器只认 v2")
    if page not in (2048, 4096, 8192, 16384):
        errs.append(f"page_size={page} 不合法")
    if hdr_size != 1660:
        errs.append(f"header_size={hdr_size}，v2 应为 1660")
    if not ksize:
        errs.append("kernel 段为空")
    if not rsize:
        errs.append("ramdisk 段为空")
    if not dsize:
        errs.append("dtb 段为空（安装器要把 dtb 单独写到 ESP，没有 dtb 会开不了机）")
    if len(data) > 64 << 20:
        errs.append("boot.img 超过 64 MiB，写不进 boot 分区")

    off = page + (ksize + page - 1) // page * page + (rsize + page - 1) // page * page
    if off + 4 <= len(data):
        if data[:8] == BOOT_MAGIC and ksize and data[page:page + 2] != b"MZ":
            errs.append("kernel 不是 PE（MZ 魔数）")
        if dsize and data[off:off + 4] != FDT_MAGIC:
            errs.append("dtb 位置不是 FDT 魔数（镜像被改动过？）")
    cmdline = data[64:576].split(b"\x00")[0]
    if not cmdline:
        errs.append("cmdline 为空")
    elif any(c < 0x20 or c > 0x7e for c in cmdline):
        errs.append("cmdline 含非 ASCII 字符")
    info = {
        "page": page, "version": ver,
        "kernel_mib": round(ksize / 1048576, 1),
        "ramdisk_mib": round(rsize / 1048576, 1),
        "dtb_kib": round(dsize / 1024, 1),
        "file_mib": round(len(data) / 1048576, 1),
        "cmdline_head": cmdline[:60].decode("ascii", "replace"),
    }
    return errs, info


def check_super(path):
    errs = []
    with open(path, "rb") as f:
        head = f.read(28)
    if len(head) < 28:
        return ["super 镜像太短"], None
    magic = struct.unpack_from("<I", head, 0)[0]
    if magic != SPARSE_MAGIC:
        return ["不是 sparse 镜像（lpmake 要带 -S；安装器只认 sparse）"], None
    blk = struct.unpack_from("<I", head, 12)[0]
    total_blks = struct.unpack_from("<I", head, 16)[0]
    expanded = blk * total_blks
    want = SUPER_MIB << 20
    if expanded != want:
        errs.append(f"展开后 {expanded} 字节（{expanded/2**30:.1f} GiB），期望 {SUPER_MIB} MiB（{want/2**30:.1f} GiB）")
    return errs, {"block_size": blk, "expanded_gib": round(expanded / 2**30, 2)}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--boot")
    ap.add_argument("--super")
    ap.add_argument("--out")
    ap.add_argument("--check-only", action="store_true")
    args = ap.parse_args()
    if not args.boot:
        ap.error("至少要给 --boot")

    data = open(args.boot, "rb").read()
    res = check_boot(data)
    errs, info = res if isinstance(res, tuple) else (res, {})
    print("== boot.img")
    for k, v in info.items():
        print(f"   {k}: {v}")
    if errs:
        print("   ✗ " + "；".join(errs))
        sys.exit(1)
    print("   ✓ 通过（v2 + kernel/ramdisk/dtb + cmdline 均在）")

    if args.check_only:
        return

    if not args.super:
        ap.error("打包发布目录需要 --super")
    serrs, sinfo = check_super(args.super)
    print("== super 镜像")
    for k, v in (sinfo or {}).items():
        print(f"   {k}: {v}")
    if serrs:
        print("   ✗ " + "；".join(serrs))
        sys.exit(1)
    print("   ✓ 通过（sparse，展开尺寸与 GK3W_SUPER_MIB 一致）")

    if not args.out:
        ap.error("打包发布目录需要 --out")
    import os
    os.makedirs(args.out, exist_ok=True)
    boot_dst = os.path.join(args.out, "boot.img")
    super_name = os.path.basename(args.super)
    with open(boot_dst, "wb") as f:
        f.write(data)
    manifest = []
    manifest.append(f"{sha256(boot_dst)}  boot.img")
    manifest.append(f"{sha256(args.super)}  {super_name}")
    with open(os.path.join(args.out, "install-artifacts.sha256"), "w", newline="\n") as f:
        f.write("\n".join(manifest) + "\n")
    print(f"== 已写入 {args.out}")
    print("   boot.img、super（原样复制/软链请自行处理）、install-artifacts.sha256")


if __name__ == "__main__":
    main()
