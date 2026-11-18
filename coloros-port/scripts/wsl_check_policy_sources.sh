#!/usr/bin/env bash
set -euo pipefail
SRC=/mnt/e/gaokun-coloros/coloros-port/work/gaokun-parts/vendor.img
M=/mnt/gaokun-vendor-check
mkdir -p "$M"
mount -t ext4 -o loop,ro "$SRC" "$M"
echo "==== gaokun vendor selinux files ===="
find "$M/etc/selinux" -maxdepth 1 -type f -printf '%f %s\n' | sort
echo "==== candidate property strings ===="
for term in vendor_camera_remapid_prop vendor_camera_skip_failed_ids_prop vendor_radio_opm_prop; do
  echo "-- $term --"
  grep -a -n -F "$term" "$M/etc/selinux"/* 2>/dev/null || true
done
echo "==== vendor property context tail ===="
grep -a -v '^#' "$M/etc/selinux/vendor_property_contexts" | tail -20
echo "==== policy magic/version ===="
file "$M/etc/selinux/precompiled_sepolicy" 2>/dev/null || true
ls -l "$M/etc/selinux/precompiled_sepolicy" 2>/dev/null || true
echo "==== final vendor image from super ===="
B=/home/cenmin/coloros-build/final-vendor-check
rm -rf "$B"
mkdir -p "$B"
python3 /mnt/e/gaokun-coloros/coloros-port/scripts/partition_inspect.py /home/cenmin/coloros-build/super-coloros-a.img --extract vendor_a "$B/vendor.img" >/dev/null
M2=/mnt/final-vendor-check
mkdir -p "$M2"
mount -t ext4 -o loop,ro "$B/vendor.img" "$M2"
find "$M2/etc/selinux" -maxdepth 1 -type f -printf '%f %s\n' | sort
sha256sum "$M2/etc/selinux/precompiled_sepolicy" "$M2/etc/selinux/vendor_property_contexts" 2>/dev/null || true
umount "$M2"
umount "$M"
