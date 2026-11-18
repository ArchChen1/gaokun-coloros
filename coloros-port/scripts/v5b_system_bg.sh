#!/bin/bash
set -euo pipefail
ROOT=/home/cenmin/v5
TREE=$ROOT/system
OUT=$ROOT/system-v5b.erofs
UUID=8e526587-69d7-562d-a908-a83699912a48
LOG=$ROOT/v5b-system-build.log
rm -f "$OUT" "$LOG" "$LOG.tmp"
{
echo "=== start $(date) ==="
stat -c 'logd mode=%a uid=%u gid=%g' $TREE/system/bin/logd
stat -c 'surf mode=%a uid=%u gid=%g' $TREE/system/bin/surfaceflinger
echo "=== mkfs.erofs (no --all-root) ==="
mkfs.erofs -zlz4 -b4096 -C65536 -U "$UUID" -L system -T 1793807531 "$OUT" "$TREE" 2>&1 | tail -8
echo "=== done $(date) ==="
ls -lh "$OUT"
dump.erofs --path /system/bin/logd "$OUT" 2>/dev/null | grep -E 'Uid|Access'
dump.erofs --path /system/bin/surfaceflinger "$OUT" 2>/dev/null | grep -E 'Uid|Access'
fsck.erofs "$OUT" 2>&1 | tail -3
echo OK
} > "$LOG.tmp" 2>&1
mv -f "$LOG.tmp" "$LOG"
touch "$ROOT/v5b.done"