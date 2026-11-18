#!/usr/bin/env bash
set -euo pipefail
CR=/home/cenmin/coloros-trees-xattr
GR=/home/cenmin/coloros-build
echo "==== ColorOS selinux top files ===="
for p in system/system system_ext product vendor odm my_product my_stock my_manifest; do
  d="$CR/$p/etc/selinux"
  if [ -d "$d" ]; then
    echo "-- $p"
    find "$d" -maxdepth 1 -type f -printf '%f %s\n' | sort
  fi
done
echo "==== ColorOS versions ===="
find "$CR" -name 'plat_sepolicy_vers.txt' -o -name 'genfs_labels_version.txt' -o -name '*sepolicy_and_mapping*.sha256' | sort | while read -r f; do
  echo "-- $f"
  filesize=$(stat -c %s "$f")
  if [ "$filesize" -lt 1000 ]; then cat "$f"; else echo "$filesize bytes"; fi
done
echo "==== Gaokun vendor policy files ===="
M=/mnt/gk-pol-audit
mkdir -p "$M"
mount -t ext4 -o loop,ro /mnt/e/gaokun-coloros/coloros-port/work/gaokun-parts/vendor.img "$M"
for f in precompiled_sepolicy precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256 precompiled_sepolicy.product_sepolicy_and_mapping.sha256 plat_pub_versioned.cil vendor_sepolicy.cil vendor_property_contexts plat_sepolicy_vers.txt genfs_labels_version.txt; do
  p="$M/etc/selinux/$f"
  [ -f "$p" ] && echo "$f $(stat -c %s "$p")" || echo "$f MISSING"
done
echo "==== Gaokun SHA contents ===="
for f in "$M"/etc/selinux/precompiled_sepolicy.*.sha256; do echo "-- $(basename "$f")"; cat "$f"; done
umount "$M"
