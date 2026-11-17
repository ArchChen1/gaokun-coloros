#!/usr/bin/env bash
set -euo pipefail
B=/home/cenmin/coloros-build/readback
mkdir -p /mnt/rb-vendor /mnt/rb-system /mnt/rb-manifest
mount -t ext4 -o loop,ro "$B/vendor.img" /mnt/rb-vendor
mount -t erofs -o loop,ro "$B/system.img" /mnt/rb-system
mount -t erofs -o loop,ro "$B/my_manifest.img" /mnt/rb-manifest
echo vendor-fstab
grep -n "ColorOS partitions" -A16 /mnt/rb-vendor/etc/fstab.gaokun3
echo system-build
grep -E "ro.build.version.(sdk|release)=" /mnt/rb-system/system/build.prop | head
echo manifest-build
grep -E "ro.product.(device|name|model)=" /mnt/rb-manifest/build.prop
umount /mnt/rb-vendor /mnt/rb-system /mnt/rb-manifest
