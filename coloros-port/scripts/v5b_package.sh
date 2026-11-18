#!/bin/bash
set -euo pipefail
CB=/home/cenmin/coloros-build
SRC=$CB/super-coloros-v5b.simg
REL=$CB/release-coloros-v5b
LOG=$CB/v5b-package.log
rm -rf "$REL" "$LOG" "$CB/v5b.package.done"; mkdir -p "$REL"
{
echo "=== start $(date) ==="
echo "=== compress super zstd -T0 -12 (no --long) ==="
zstd -T0 -12 -f "$SRC" -o "$REL/super.img.zst"
echo "=== integrity test ==="
zstd -t "$REL/super.img.zst" 2>&1 | tail -2
echo "=== boot.img ==="
cp -f "$CB/boot-coloros.img" "$REL/boot.img"
cd "$REL"
sha256sum boot.img super.img.zst > install-artifacts.sha256
cat install-artifacts.sha256
ls -l
echo "=== done $(date) ==="
} > "$LOG.tmp" 2>&1
mv -f "$LOG.tmp" "$LOG"
touch "$CB/v5b.package.done"