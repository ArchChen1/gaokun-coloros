#!/bin/bash
set -euo pipefail
BASE=/home/cenmin/coloros-build/policy-src
SRC=/mnt/e/gaokun-coloros/coloros-port/work/opd2513
GK=/mnt/e/gaokun-coloros/coloros-port/work/gaokun-parts/vendor.img
M="$BASE/mnt"
mkdir -p "$M/source" "$M/system" "$M/system_ext" "$M/product" "$M/vendor" "$M/odm" "$M/gaokun_vendor"
mount -t erofs -o loop,ro "$SRC/system.img" "$M/system"
mount -t erofs -o loop,ro "$SRC/system_ext.img" "$M/system_ext"
mount -t erofs -o loop,ro "$SRC/product.img" "$M/product"
mount -t erofs -o loop,ro "$SRC/vendor.img" "$M/vendor"
mount -t erofs -o loop,ro "$SRC/odm.img" "$M/odm"
mount -t ext4 -o loop,ro "$GK" "$M/gaokun_vendor"

for item in system system_ext product vendor odm; do
  case "$item" in
    system) d="$M/system/system/etc/selinux" ;;
    system_ext) d="$M/system_ext/system_ext/etc/selinux" ;;
    product) d="$M/product/product/etc/selinux" ;;
    vendor) d="$M/vendor/etc/selinux" ;;
    odm) d="$M/odm/etc/selinux" ;;
  esac
  if [ -d "$d" ]; then cp -a "$d"/. "$BASE/$item"/; fi
done
d="$M/gaokun_vendor/etc/selinux"
if [ -d "$d" ]; then cp -a "$d"/. "$BASE/gaokun_vendor"/; fi

for d in system system_ext product vendor odm gaokun_vendor; do
  echo "==== $d"
  find "$BASE/$d" -maxdepth 2 -type f -printf '%P %s\n' | sort
done

echo "==== versions"
for d in system system_ext product vendor odm gaokun_vendor; do
  for f in plat_sepolicy_vers.txt genfs_labels_version.txt; do
    if [ -f "$BASE/$d/$f" ]; then printf '%s/%s=' "$d" "$f"; cat "$BASE/$d/$f"; fi
  done
done

echo "==== cil heads"
for f in "$BASE/system"/*.cil "$BASE/system_ext"/*.cil "$BASE/product"/*.cil "$BASE/vendor"/plat_pub_versioned.cil "$BASE/gaokun_vendor"/plat_pub_versioned.cil "$BASE/gaokun_vendor"/vendor_sepolicy.cil; do
  [ -f "$f" ] || continue
  echo "-- $f"
  head -c 500 "$f" | tr '\n' ' ' | cut -c1-500
  echo
done

umount "$M/gaokun_vendor" "$M/odm" "$M/vendor" "$M/product" "$M/system_ext" "$M/system"
rmdir "$M/source" "$M/gaokun_vendor" "$M/odm" "$M/vendor" "$M/product" "$M/system_ext" "$M/system"