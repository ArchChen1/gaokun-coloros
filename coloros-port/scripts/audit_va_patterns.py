#!/usr/bin/env python3
from pathlib import Path
import struct
files = [
    '/home/cenmin/v25-system/tree/system/lib64/libutils.so',
    '/home/cenmin/v25-system/tree/system/lib/libutils.so',
    '/home/cenmin/audit-v36/product/lib64/libutils.so',
    '/home/cenmin/audit-v36/product/lib/libutils.so',
    '/home/cenmin/v25-system/tree/system/bin/gsid',
]
for f in files:
    data = Path(f).read_bytes()
    found = []
    for name, word in [('b2409be8',0xb2409be8),('b240bbe9',0xb240bbe9),('b240dfe0',0xb240dfe0)]:
        pos = data.find(struct.pack('<I', word))
        found.append(name + ':' + (str(pos) if pos >= 0 else 'none'))
    print(Path(f).name, Path(f).stat().st_size, ' '.join(found))