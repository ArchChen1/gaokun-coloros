#!/usr/bin/env bash
set -euo pipefail
B=/home/cenmin/coloros-build/boot-unpack
OUT=/mnt/e/gaokun-coloros/coloros-port/out/esp-slot-a-coloros
rm -rf "$OUT"
mkdir -p "$OUT"
cp -f "$B/kernel" "$OUT/Image"
cp -f "$B/dtb" "$OUT/gaokun3.dtb"
cp -f "$B/ramdisk.new" "$OUT/ramdisk.img"
chmod 644 "$OUT"/*
cd "$OUT"
sha256sum Image gaokun3.dtb ramdisk.img > SHA256SUMS
cat SHA256SUMS
ls -lh
