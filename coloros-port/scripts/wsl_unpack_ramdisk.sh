#!/usr/bin/env bash
set -euo pipefail
B=/home/cenmin/coloros-build/boot-unpack
R=$B/ramdisk-tree
rm -rf "$R"
mkdir -p "$R"
cd "$R"
gzip -dc "$B/ramdisk" | cpio -idmu --quiet
echo "---- fstab files ----"
find "$R" -maxdepth 3 -name "fstab*" -print
echo "---- entries ----"
find "$R" -maxdepth 2 -mindepth 1 -printf "%y %p
" | head -60
echo "---- size ----"
du -sh "$R"
