#!/usr/bin/env bash
set -euo pipefail
SRC=/home/cenmin/coloros-build
V=/home/cenmin/coloros-build/vendor-gaokun.img
M=/mnt/gaokun-vendor-edit
cp /mnt/e/gaokun-coloros/coloros-port/work/gaokun-parts/vendor.img "$V"
chmod 644 "$V"
mkdir -p "$M"
mount -o loop "$V" "$M"
cat >> "$M/etc/fstab.gaokun3" <<'EOF'

# ColorOS partitions added by the port.
system       /system       erofs  ro                                wait,logical,first_stage_mount,slotselect
system_ext   /system_ext   erofs  ro                                wait,logical,first_stage_mount,slotselect
product      /product      erofs  ro                                wait,logical,first_stage_mount,slotselect
odm          /odm          erofs  ro                                wait,logical,first_stage_mount,slotselect
my_product   /my_product   erofs  ro                                wait,logical,first_stage_mount,slotselect,nofail
my_stock     /my_stock     erofs  ro                                wait,logical,first_stage_mount,slotselect,nofail
my_manifest  /my_manifest  erofs  ro                                wait,logical,first_stage_mount,slotselect,nofail
my_region    /my_region    erofs  ro                                wait,logical,first_stage_mount,slotselect,nofail
my_engineering /my_engineering erofs ro                            wait,logical,first_stage_mount,slotselect,nofail
my_heytap    /my_heytap    erofs  ro                                wait,logical,first_stage_mount,slotselect,nofail
my_carrier   /my_carrier   erofs  ro                                wait,logical,first_stage_mount,slotselect,nofail
my_bigball   /my_bigball   erofs  ro                                wait,logical,first_stage_mount,slotselect,nofail
EOF
sync
umount "$M"
echo "patched vendor fstab"
grep -n 'ColorOS partitions' -A20 "$M/etc/fstab.gaokun3" 2>/dev/null || true
