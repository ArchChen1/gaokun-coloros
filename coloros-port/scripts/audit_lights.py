#!/usr/bin/env python3
from pathlib import Path
import struct
p = Path('/home/cenmin/audit-v36/vendor/bin/hw/android.hardware.light-service.gaokun3')
data = p.read_bytes()
for name, word in [('old',0x53087d08),('new',0x39400048)]:
    needle = struct.pack('<I', word)
    pos = 0
    hits = []
    while True:
        pos = data.find(needle, pos)
        if pos < 0: break
        hits.append(pos)
        pos += 1
    print(name, [hex(x) for x in hits[:20]], 'count', len(hits))