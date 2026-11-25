#!/usr/bin/env python3
"""boot image v0–v2 解析与打包（本机只有 v2、页 2048、带 dtb、无 second/recovery_dtbo）。

id 规则（vendor/gaokun-android/tools/gk3boot/core/src/bootimg.c:10 与 :85-100）：
  id[0:20] = SHA1( kernel‖le32(kernel_size), ramdisk‖le32(ramdisk_size),
                   second‖le32(second_size), [recovery_dtbo‖le32(len)], [dtb‖le32(len)] )

用法：
  bootimg_v2.py parse <boot.img>
  bootimg_v2.py pack  <out.img> --kernel K --ramdisk R --dtb D --cmdline "<...>"
"""
import hashlib
import struct
import sys

MAGIC = b"ANDROID!"
PAGE = 2048
HEADER_SIZE_V2 = 1660


def le32(*vals):
    return struct.pack("<%dI" % len(vals), *vals)


def compute_id(kernel, ramdisk, second, dtb, version, rdtbo=b""):
    h = hashlib.sha1()
    for blob in (kernel, ramdisk, second):
        h.update(blob)
        h.update(le32(len(blob)))
    if version >= 1:
        h.update(rdtbo)
        h.update(le32(len(rdtbo)))
    if version >= 2:
        h.update(dtb)
        h.update(le32(len(dtb)))
    return h.digest()


def align(n):
    return (n + PAGE - 1) // PAGE * PAGE


def parse(path):
    data = open(path, "rb").read()
    assert data[:8] == MAGIC, "not a boot image"
    (ks, ka, rs, ra, ss, sa, ta, page, ver, osv) = struct.unpack_from("<10I", data, 8)
    cmdline = data[64:576].split(b"\x00")[0]
    extra_cmdline = data[608:1632].split(b"\x00")[0]
    idb = data[576:608]
    rdtbo_size, rdtbo_off, hsize = struct.unpack_from("<IQI", data, 1632)
    dtb_size, dtb_addr = struct.unpack_from("<IQ", data, 1648)

    koff = page
    roff = koff + align(ks)
    soff = roff + align(rs)
    rdoff = soff + align(ss)
    dtboff = rdoff + align(rdtbo_size)

    kernel = data[koff:koff + ks]
    ramdisk = data[roff:roff + rs]
    second = data[soff:soff + ss] if ss else b""
    rdtbo = data[rdoff:rdoff + rdtbo_size] if rdtbo_size else b""
    dtb = data[dtboff:dtboff + dtb_size] if dtb_size else b""

    calc = compute_id(kernel, ramdisk, second, dtb, ver, rdtbo)
    print(f"page={page} version={ver} os_version=0x{osv:08x} header_size={hsize}")
    print(f"kernel={ks} ramdisk={rs} second={ss} recovery_dtbo={rdtbo_size} dtb={dtb_size}")
    print(f"addrs: kernel=0x{ka:x} ramdisk=0x{ra:x} tags=0x{ta:x} dtb=0x{dtb_addr:x}")
    print(f"cmdline({len(cmdline)}+{len(extra_cmdline)}): {(cmdline + extra_cmdline).decode(errors='replace')}")
    print(f"id stored={idb[:20].hex()}")
    print(f"id calc  ={calc.hex()}  -> {'OK' if calc == idb[:20] else 'MISMATCH'}")
    return dict(kernel=kernel, ramdisk=ramdisk, dtb=dtb, os_version=osv, cmdline=cmdline,
                ok=(calc == idb[:20]))


def pack(out, kernel, ramdisk, dtb, cmdline, os_version=0, kaddr=0x10008000,
         raddr=0x11000000, tags=0x10000100, daddr=0x11f00000):
    ident = compute_id(kernel, ramdisk, b"", dtb, 2)
    hdr = bytearray(HEADER_SIZE_V2)
    hdr[0:8] = MAGIC
    struct.pack_into("<10I", hdr, 8, len(kernel), kaddr, len(ramdisk), raddr,
                     0, 0, tags, PAGE, 2, os_version)
    # gk3boot 的 base cmdline = cmdline[512] + extra_cmdline[1024] 直接拼接（cmdline.c:92-102）
    hdr[64:64 + min(len(cmdline), 512)] = cmdline[:512]
    rest = cmdline[512:]
    if len(rest) > 1024:
        sys.exit("cmdline 超过 1536 字节")
    hdr[608:608 + len(rest)] = rest
    hdr[576:596] = ident
    struct.pack_into("<IQI", hdr, 1632, 0, 0, HEADER_SIZE_V2)
    struct.pack_into("<IQ", hdr, 1648, len(dtb), daddr)
    body = hdr.ljust(PAGE, b"\x00") + kernel.ljust(align(len(kernel)), b"\x00")
    body += ramdisk.ljust(align(len(ramdisk)), b"\x00")
    body += dtb.ljust(align(len(dtb)), b"\x00")
    open(out, "wb").write(body)
    print(f"packed {out}: {len(body)} bytes, id={ident.hex()}")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd, img = sys.argv[1], sys.argv[2]
    if cmd == "parse":
        sys.exit(0 if parse(img)["ok"] else 1)
    if cmd == "pack":
        kw = {}
        args = sys.argv[3:]
        while args:
            k = args.pop(0)
            if k == "--kernel":
                kw["kernel"] = open(args.pop(0), "rb").read()
            elif k == "--ramdisk":
                kw["ramdisk"] = open(args.pop(0), "rb").read()
            elif k == "--dtb":
                kw["dtb"] = open(args.pop(0), "rb").read()
            elif k == "--cmdline":
                kw["cmdline"] = args.pop(0).encode()
            elif k == "--os-version":
                kw["os_version"] = int(args.pop(0), 0)
            else:
                sys.exit("unknown option " + k)
        pack(img, **kw)
        return
    sys.exit("unknown command")


if __name__ == "__main__":
    main()
