#!/bin/bash
set -euo pipefail

CB=/home/cenmin/coloros-build
SRC=$CB/super-coloros-v28.simg
REL=$CB/release-coloros-v28
LOG=$CB/v28-package.log

rm -rf "$REL"
mkdir -p "$REL"
{
  echo "=== v28 package $(date -Is) ==="
  cp -f "$CB/boot-coloros.img" "$REL/boot.img"
  time zstd -T0 -12 -f "$SRC" -o "$REL/super.img.zst"
  zstd -t "$REL/super.img.zst"
  cd "$REL"
  sha256sum boot.img super.img.zst > install-artifacts.sha256
  cat install-artifacts.sha256
  ls -lh
  echo "=== done $(date -Is) ==="
} >"$LOG" 2>&1
tail -40 "$LOG"
echo V28_PACKED
