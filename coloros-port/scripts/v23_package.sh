#!/bin/bash
set -euo pipefail
CB=/home/cenmin/coloros-build
SRC=$CB/super-coloros-v23.simg
REL=$CB/release-coloros-v23
LOG=$CB/v23-package.log
rm -rf "$REL"
mkdir -p "$REL"
{
  echo "=== v23 package $(date -Is) ==="
  cp -f "$CB/boot-coloros.img" "$REL/boot.img"
  md5sum "$SRC" | tee "$REL/source-super.md5"
  echo "=== compress zstd -T0 -12 (no long) ==="
  time zstd -T0 -12 -f "$SRC" -o "$REL/super.img.zst"
  echo "=== verify compressed stream ==="
  zstd -t "$REL/super.img.zst"
  cd "$REL"
  sha256sum boot.img super.img.zst > install-artifacts.sha256
  cat install-artifacts.sha256
  ls -lh
  echo "=== done $(date -Is) ==="
} > "$LOG" 2>&1
tail -50 "$LOG"
echo V23_PACKED