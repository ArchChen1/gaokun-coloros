#!/usr/bin/env bash
set -euo pipefail
SRC=/home/cenmin/coloros-build/vendor-gaokun.img
TMP=/home/cenmin/coloros-build/vendor-tree
OUT=/home/cenmin/coloros-build/vendor-gaokun-clean.img
M=/mnt/gaokun-vendor-edit
rm -rf "$TMP"
mkdir -p "$TMP" "$M"
mount -o loop,ro "$SRC" "$M"
cp -a "$M"/. "$TMP"/
umount "$M"

# Remove the previous appended block and rebuild it cleanly.
sed -i '/^# ColorOS partitions added by the port\./,$d' "$TMP/etc/fstab.gaokun3"
cat >> "$TMP/etc/fstab.gaokun3" <<'EOF'

# ColorOS read-only system partitions.
system          /system          erofs  ro  wait,logical,first_stage_mount,slotselect
system_ext      /system_ext      erofs  ro  wait,logical,first_stage_mount,slotselect
product         /product         erofs  ro  wait,logical,first_stage_mount,slotselect
odm             /odm             erofs  ro  wait,logical,first_stage_mount,slotselect
my_product      /my_product      erofs  ro  wait,logical,first_stage_mount,slotselect,nofail
my_stock        /my_stock        erofs  ro  wait,logical,first_stage_mount,slotselect,nofail
my_manifest     /my_manifest     erofs  ro  wait,logical,first_stage_mount,slotselect,nofail
my_region       /my_region       erofs  ro  wait,logical,first_stage_mount,slotselect,nofail
my_engineering  /my_engineering  erofs  ro  wait,logical,first_stage_mount,slotselect,nofail
my_heytap       /my_heytap       erofs  ro  wait,logical,first_stage_mount,slotselect,nofail
my_carrier      /my_carrier      erofs  ro  wait,logical,first_stage_mount,slotselect,nofail
my_bigball      /my_bigball      erofs  ro  wait,logical,first_stage_mount,slotselect,nofail

# OPlus app overlays used by ColorOS at first boot.
overlay-overlay /product/app                  overlay ro,seclabel,noatime,redirect_dir=nofollow,userxattr,lowerdir=/my_region/app:/my_product/app:/my_heytap/app:/my_stock/app:/my_engineering/app:/product/app overlayfs_remove_missing_lowerdir
overlay-overlay /product/priv-app             overlay ro,seclabel,noatime,redirect_dir=nofollow,userxattr,lowerdir=/my_region/priv-app:/my_product/priv-app:/my_heytap/priv-app:/my_stock/priv-app:/my_engineering/priv-app:/product/priv-app overlayfs_remove_missing_lowerdir
overlay-overlay /product/lib64                overlay ro,seclabel,noatime,redirect_dir=nofollow,userxattr,lowerdir=/my_region/lib64:/my_product/lib64:/my_heytap/lib64:/my_stock/lib64:/my_engineering/lib64:/product/lib64 overlayfs_remove_missing_lowerdir
overlay-overlay /product/lib                  overlay ro,seclabel,noatime,redirect_dir=nofollow,userxattr,lowerdir=/my_region/lib:/my_product/lib:/my_heytap/lib:/my_stock/lib:/my_engineering/lib:/product/lib overlayfs_remove_missing_lowerdir
overlay-overlay /product/etc/permissions      overlay ro,seclabel,redirect_dir=nofollow,userxattr,lowerdir=/my_product/product_overlay/etc/permissions:/product/etc/permissions overlayfs_remove_missing_lowerdir
overlay-overlay /product/framework            overlay ro,seclabel,redirect_dir=nofollow,userxattr,lowerdir=/my_product/product_overlay/framework:/product/framework overlayfs_remove_missing_lowerdir
EOF

# Recreate the vendor image with the same 308 MiB size.
rm -f "$OUT"
truncate -s 536870912 "$OUT"
mkfs.ext4 -q -F -b 4096 -I 256 -m 0 -L vendor "$OUT"
mount -o loop "$OUT" "$M"
cp -a "$TMP"/. "$M"/
sync
umount "$M"
echo "rebuilt $OUT"
