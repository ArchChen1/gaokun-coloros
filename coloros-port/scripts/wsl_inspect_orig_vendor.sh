#!/usr/bin/env bash
set -euo pipefail
M=/mnt/gk-orig
mkdir -p "$M"
mount -t ext4 -o loop,ro /mnt/e/gaokun-coloros/coloros-port/work/gaokun-parts/vendor.img "$M"
echo "bytes=$(wc -c < "$M/etc/fstab.gaokun3")"
echo -n "label="; getfattr -n security.selinux --only-values "$M/etc/fstab.gaokun3" 2>/dev/null || echo MISSING
echo
tail -n 25 "$M/etc/fstab.gaokun3"
umount "$M"
