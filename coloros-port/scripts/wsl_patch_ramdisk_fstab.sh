#!/usr/bin/env bash
set -euo pipefail
B=/home/cenmin/coloros-build/boot-unpack
R=$B/ramdisk-tree
python3 - <<'PY'
from pathlib import Path
p = Path('/home/cenmin/coloros-build/boot-unpack/ramdisk-tree/fstab.gaokun3')
lines = p.read_text().splitlines()
logical = {'system', 'system_ext', 'product', 'vendor', 'overlay-overlay'}
kept = []
for line in lines:
    s = line.strip()
    if s and not s.startswith('#'):
        first = s.split(None, 1)[0]
        if first in logical:
            continue
    kept.append(line.rstrip())
extra = [
    '',
    '# ColorOS logical partitions (first-stage fstab)',
    'system          /system          erofs  ro  wait,logical,first_stage_mount,slotselect',
    'system_ext      /system_ext      erofs  ro  wait,logical,first_stage_mount,slotselect',
    'product         /product         erofs  ro  wait,logical,first_stage_mount,slotselect',
    'vendor          /vendor          ext4   ro,barrier=1  wait,logical,first_stage_mount,slotselect',
    'odm             /odm             erofs  ro  wait,logical,first_stage_mount,slotselect',
    'my_product      /my_product      erofs  ro  wait,logical,first_stage_mount,slotselect,nofail',
    'my_stock        /my_stock        erofs  ro  wait,logical,first_stage_mount,slotselect,nofail',
    'my_manifest     /my_manifest     erofs  ro  wait,logical,first_stage_mount,slotselect,nofail',
    'my_region       /my_region       erofs  ro  wait,logical,first_stage_mount,slotselect,nofail',
    'my_engineering  /my_engineering  erofs  ro  wait,logical,first_stage_mount,slotselect,nofail',
    'my_heytap       /my_heytap       erofs  ro  wait,logical,first_stage_mount,slotselect,nofail',
    'my_carrier      /my_carrier      erofs  ro  wait,logical,first_stage_mount,slotselect,nofail',
    'my_bigball      /my_bigball      erofs  ro  wait,logical,first_stage_mount,slotselect,nofail',
]
p.write_text('\n'.join(kept + extra) + '\n')
print(p.read_text())

PY
# Rebuild the ramdisk deterministically, preserving ownership/modes.
cd "$R"
find . -print0 | cpio --null -o --format=newc --quiet | gzip -9 > "$B/ramdisk.new"
ls -lh "$B/ramdisk" "$B/ramdisk.new"
