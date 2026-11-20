#!/bin/bash
set -euo pipefail
CB=/home/cenmin/coloros-build
SRC=$CB/super-coloros-v24.simg
REL=$CB/release-coloros-v24
LOG=$CB/v24-package.log
rm -rf "$REL"; mkdir -p "$REL"
{
  echo "=== v24 package $(date -Is) ==="
  cp -f "$CB/boot-coloros.img" "$REL/boot.img"
  time zstd -T0 -12 -f "$SRC" -o "$REL/super.img.zst"
  zstd -t "$REL/super.img.zst"
  cd "$REL"
  sha256sum boot.img super.img.zst > install-artifacts.sha256
  cat install-artifacts.sha256
  ls -lh
  echo "=== done $(date -Is) ==="
} >"$LOG" 2>&1
tail -50 "$LOG"
echo V24_PACKED