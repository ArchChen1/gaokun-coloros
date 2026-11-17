#!/usr/bin/env bash
set -euo pipefail
V=/home/cenmin/coloros-build/vendor-gaokun-patched.img
M=/mnt/gk-check
mkdir -p "$M"
mount -o loop,ro "$V" "$M"
echo -n "label="
getfattr -n security.selinux --only-values "$M/etc/fstab.gaokun3"
echo
grep -n "ColorOS logical" -A20 "$M/etc/fstab.gaokun3"
echo -n "physical_lines="
grep -c "^/dev/block" "$M/etc/fstab.gaokun3" || true
umount "$M"
