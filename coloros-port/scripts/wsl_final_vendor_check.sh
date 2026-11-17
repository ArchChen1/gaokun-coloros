#!/usr/bin/env bash
set -euo pipefail
B=/home/cenmin/coloros-build/final-readback
S=/home/cenmin/coloros-build/super-coloros-a.img
P=/mnt/e/gaokun-coloros/coloros-port/scripts/partition_inspect.py
M=/mnt/final-vendor
rm -rf "$B"
mkdir -p "$B" "$M"
python3 "$P" "$S" --extract vendor_a "$B/vendor.img" >/dev/null
mount -t ext4 -o loop,ro "$B/vendor.img" "$M"
echo -n "label="
getfattr -n security.selinux --only-values "$M/etc/fstab.gaokun3"
echo
grep -n "ColorOS logical" -A8 "$M/etc/fstab.gaokun3"
umount "$M"
