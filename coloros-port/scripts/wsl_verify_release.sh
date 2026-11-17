#!/usr/bin/env bash
set -euo pipefail
REL=/home/cenmin/coloros-build/release-coloros-a
OUT=/mnt/e/gaokun-coloros/coloros-port/out/release-coloros-a
rm -rf "$OUT"
mkdir -p "$OUT"
cp "$REL/boot.img" "$OUT/boot.img"
cp "$REL/super.img.zst" "$OUT/super.img.zst"
cp "$REL/install-artifacts.sha256" "$OUT/install-artifacts.sha256"
chmod 644 "$OUT"/*
cd "$OUT"
sha256sum -c install-artifacts.sha256
# Decode-test the zstd stream without writing the full image.
zstd -t super.img.zst
ls -lh "$OUT"
