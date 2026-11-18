#!/bin/bash
set -euo pipefail
ROOT=/home/cenmin/v5
TREE=$ROOT/system
OUT=$ROOT/system-v5b.erofs
UUID=8e526587-69d7-562d-a908-a83699912a48
rm -f "$OUT"

echo "=== pre-check tree ownership (must be 1036 for logd) ==="
stat -c 'logd  mode=%a uid=%u gid=%g' $TREE/system/bin/logd
stat -c 'surf  mode=%a uid=%u gid=%g' $TREE/system/bin/surfaceflinger

echo
echo "=== build erofs WITHOUT --all-root (preserve uid/gid) ==="
time mkfs.erofs \
  -zlz4 \
  -b4096 \
  -C65536 \
  -U "$UUID" \
  -L system \
  -T 1793807531 \
  "$OUT" "$TREE" 2>&1 | tail -8

echo
echo "=== verify ==="
ls -l "$OUT"
dump.erofs -s "$OUT" 2>&1 | grep -Ei 'blocks|inode count|feature|uuid'
echo "--- ownership in shipped image (want logd uid=1036) ---"
for f in /system/bin/logd /system/bin/surfaceflinger /system/bin/init; do
  printf '%-28s ' "$f"; dump.erofs --path "$f" "$OUT" 2>/dev/null | grep -E 'Uid|Access' | tr '\n' ' '; echo
done
echo "--- xattr check ---"
dump.erofs --path /system/lib64/libEGL.so "$OUT" 2>/dev/null | grep -Ei 'xattr|selinux' || true
echo "--- fsck ---"
fsck.erofs "$OUT" 2>&1 | tail -3
echo SYSTEM_REBUILT_OK