#!/usr/bin/env bash
set -euo pipefail
UNPACK=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/unpack_bootimg
B=/home/cenmin/coloros-build/boot-verify
R=$B/ramdisk-tree
rm -rf "$B"
mkdir -p "$B" "$R"
"$UNPACK" --boot_img /home/cenmin/coloros-build/boot-coloros.img --out "$B" >/dev/null
cd "$R"
gzip -dc "$B/ramdisk" | cpio -idmu --quiet
echo "---- logical fstab ----"
grep -n -E "^(system|system_ext|product|vendor|odm|my_)" "$R/fstab.gaokun3"
