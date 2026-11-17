#!/usr/bin/env bash
set -euo pipefail
IMG2SIMG=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/img2simg
B=/home/cenmin/coloros-build
REL=$B/release-coloros-a
mkdir -p "$REL"
cp /mnt/e/gaokun-coloros/coloros-port/work/gaokun-rc4/../gaokun-rc4/boot.img "$REL/boot.img" 2>/dev/null || cp /mnt/e/gaokun-coloros/coloros-port/inputs/Gaokun-Androidv1.0.0-rc.4/boot.img "$REL/boot.img"
echo "[1/3] sparse super"
"$IMG2SIMG" "$B/super-coloros-a.img" "$REL/super.sparse.img"
echo "[2/3] zstd"
zstd -T0 -19 --long=31 -f "$REL/super.sparse.img" -o "$REL/super.img.zst"
echo "[3/3] manifest"
cd "$REL"
sha256sum boot.img super.img.zst > install-artifacts.sha256
rm -f super.sparse.img
ls -lh
cat install-artifacts.sha256
