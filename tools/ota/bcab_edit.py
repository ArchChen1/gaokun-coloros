#!/usr/bin/env python3
"""misc 里 bootloader_control（BCAB）的查看与改写。

布局（tools/gk3boot/core/src/bcab.c，misc 偏移 2048，32 字节）：
  0   slot_suffix[4]      "_a\0\0"
  4   magic u32           "BCAB" = 0x42414342
  8   version u8          1
  9   ctrl u16（跨 9-10）  bits0-2 nb_slot, bits3-5 recovery_tries, bits6-8 merge_status
  12  slot_info[4] u16    每槽: pri(bits0-3) tries(bits4-6) successful(bit7) verity(bit8)
  28  crc32 u32            zlib crc32 of bytes[0:28]

用法：
  bcab_edit.py show <misc.bin>
  bcab_edit.py set <in.bin> <out.bin> a:pri:tries:ok b:pri:tries:ok
"""
import sys
import zlib

OFF = 0x800
SIZE = 32


def u16(b, off):
    return b[off] | (b[off + 1] << 8)


def put_u16(b, off, v):
    b[off] = v & 0xFF
    b[off + 1] = (v >> 8) & 0xFF


def decode(bc):
    assert bc[4:8] == b"BCAB", "magic 不是 BCAB"
    ctrl = u16(bc, 9)
    slots = []
    for i in range(2):
        v = u16(bc, 12 + 2 * i)
        slots.append({"pri": v & 15, "tries": (v >> 4) & 7, "ok": (v >> 7) & 1,
                      "verity": (v >> 8) & 1})
    return {
        "suffix": bc[0:2].decode("ascii", "replace"),
        "version": bc[8],
        "nb_slot": ctrl & 7,
        "recovery_tries": (ctrl >> 3) & 7,
        "merge_status": (ctrl >> 6) & 7,
        "slots": slots,
        "crc_stored": int.from_bytes(bc[28:32], "little"),
        "crc_calc": zlib.crc32(bc[:28]),
    }


def encode(bc, suffix, slots):
    bc[0] = ord("_")
    bc[1] = ord(suffix[-1])
    for i, s in enumerate(slots):
        v = u16(bc, 12 + 2 * i) & ~0x01FF
        v |= s["pri"] & 15
        v |= (s["tries"] & 7) << 4
        v |= (s["ok"] & 1) << 7
        v |= (s["verity"] & 1) << 8
        put_u16(bc, 12 + 2 * i, v)
    bc[28:32] = zlib.crc32(bc[:28]).to_bytes(4, "little")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    data = bytearray(open(sys.argv[2], "rb").read())
    if len(data) < OFF + SIZE:
        sys.exit("文件不足 2080 字节")
    bc = data[OFF:OFF + SIZE]
    if cmd == "show":
        info = decode(bc)
        print(f"suffix={info['suffix']} version={info['version']} nb_slot={info['nb_slot']} "
              f"recovery_tries={info['recovery_tries']} merge={info['merge_status']}")
        for i, s in enumerate(info["slots"]):
            print(f"  slot_{'ab'[i]}: pri={s['pri']} tries={s['tries']} ok={s['ok']} verity={s['verity']}")
        ok = info["crc_stored"] == info["crc_calc"]
        print(f"crc stored={info['crc_stored']:08x} calc={info['crc_calc']:08x} -> {'OK' if ok else 'MISMATCH'}")
        sys.exit(0 if ok else 1)
    if cmd == "set":
        if len(sys.argv) < 5:
            sys.exit(__doc__)
        info = decode(bc)
        for spec in sys.argv[4:6]:
            name, pri, tries, okv = spec.split(":")
            idx = "ab".index(name)
            info["slots"][idx].update(pri=int(pri), tries=int(tries), ok=int(okv))
        encode(bc, info["suffix"], info["slots"])
        data[OFF:OFF + SIZE] = bc
        open(sys.argv[3], "wb").write(data)
        print("written", sys.argv[3])
        info = decode(bc)
        for i, s in enumerate(info["slots"]):
            print(f"  slot_{'ab'[i]}: pri={s['pri']} tries={s['tries']} ok={s['ok']}")
        print(f"crc={info['crc_calc']:08x}")
        return
    sys.exit("未知子命令")


if __name__ == "__main__":
    main()
