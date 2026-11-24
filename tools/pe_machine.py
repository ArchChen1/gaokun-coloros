#!/usr/bin/env python3
"""检查 PE 文件的 machine 字段，确认产物是对应架构的原生二进制。

用法：
    pe_machine.py 0xAA64 <file>...     # ARM64
    pe_machine.py 0x8664 <file>...     # x86_64

在 Windows-on-ARM（gaokun3）上，x64 的后端会靠模拟跑起来，功能看着一样、启动慢且测不出问题，
所以安装器的 CI 一律断言 0xAA64。
"""
import struct
import sys


def machine(path: str) -> int:
    with open(path, "rb") as f:
        data = f.read()
    e_lfanew = struct.unpack("<I", data[0x3C:0x40])[0]
    if data[e_lfanew:e_lfanew + 4] != b"PE\0\0":
        raise ValueError(f"{path}: 不是 PE 文件")
    return struct.unpack("<H", data[e_lfanew + 4:e_lfanew + 6])[0]


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    want = int(argv[1], 16)
    bad = 0
    for path in argv[2:]:
        try:
            got = machine(path)
        except (OSError, ValueError, struct.error) as e:
            print(f"FAIL {e}", file=sys.stderr)
            bad += 1
            continue
        ok = got == want
        print(f"{'OK  ' if ok else 'FAIL'} {path}: machine 0x{got:04X}")
        bad += 0 if ok else 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
