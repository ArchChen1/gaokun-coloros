#!/usr/bin/env bash
set -euo pipefail
UNPACK=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/unpack_bootimg
B=/home/cenmin/coloros-build/boot-unpack
SRC=/mnt/e/gaokun-coloros/coloros-port/inputs/Gaokun-Androidv1.0.0-rc.4/boot.img
rm -rf "$B"
mkdir -p "$B"
"$UNPACK" --boot_img "$SRC" --out "$B"
ls -lh "$B"
file "$B"/* 2>/dev/null || true
