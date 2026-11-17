#!/usr/bin/env bash
set -euo pipefail
SRC=/mnt/e/gaokun-coloros/coloros-port/work/gaokun-parts/vendor.img
DST=/home/cenmin/coloros-build/vendor-gaokun-patched.img
M=/mnt/gk-orig-edit
cp "$SRC" "$DST"
chmod 644 "$DST"
mkdir -p "$M"
mount -o loop "$DST" "$M"
python3 - <<'PY'
import os
from pathlib import Path
p = Path('/mnt/gk-orig-edit/etc/fstab.gaokun3')
raw = p.read_text()
lines = raw.splitlines()
keep = []
filtered = {'system', 'system_ext', 'product', 'vendor', 'overlay-overlay'}
for line in lines:
    s = line.strip()
    if not s or s.startswith('#'):
        continue
    first = s.split(None, 1)[0]
    if first in filtered:
        continue
    keep.append(line.rstrip())
extra = [
    '',
    '# ColorOS logical partitions and overlays',
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
    'overlay-overlay /product/app     overlay ro,seclabel,noatime,redirect_dir=nofollow,userxattr,lowerdir=/my_region/app:/my_product/app:/my_heytap/app:/my_stock/app:/my_engineering/app:/product/app overlayfs_remove_missing_lowerdir',
    'overlay-overlay /product/priv-app overlay ro,seclabel,noatime,redirect_dir=nofollow,userxattr,lowerdir=/my_region/priv-app:/my_product/priv-app:/my_heytap/priv-app:/my_stock/priv-app:/my_engineering/priv-app:/product/priv-app overlayfs_remove_missing_lowerdir',
    'overlay-overlay /product/lib64   overlay ro,seclabel,noatime,redirect_dir=nofollow,userxattr,lowerdir=/my_region/lib64:/my_product/lib64:/my_heytap/lib64:/my_stock/lib64:/my_engineering/lib64:/product/lib64 overlayfs_remove_missing_lowerdir',
    'overlay-overlay /product/lib     overlay ro,seclabel,noatime,redirect_dir=nofollow,userxattr,lowerdir=/my_region/lib:/my_product/lib:/my_heytap/lib:/my_stock/lib:/my_engineering/lib:/product/lib overlayfs_remove_missing_lowerdir',
]
out = '\n'.join(keep + extra) + '\n'
data = out.encode()
if len(data) > len(raw.encode()):
    raise SystemExit(f'new fstab too long: {len(data)} > {len(raw.encode())}')
with p.open('r+b') as f:
    f.seek(0)
    f.write(data)
    f.truncate(len(data))
    f.flush()
    os.fsync(f.fileno())
print('wrote', len(data), 'bytes; original', len(raw.encode()))

PY
sync
umount "$M"
echo "label:"; getfattr -n security.selinux --only-values "$M/etc/fstab.gaokun3" 2>/dev/null || true
