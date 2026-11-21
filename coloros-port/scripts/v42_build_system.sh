#!/bin/bash
set -euo pipefail

SRC=/home/cenmin/v38-system/tree
TREE=$(mktemp -d /home/cenmin/v42-system-tree.XXXXXX)
OUT=/home/cenmin/coloros-build/v42/system-v42.erofs
PATCHER=/mnt/e/gaokun-coloros/coloros-port/scripts/patch_sf_waits.py
PATCHED="$TREE/.surfaceflinger.patched"
MKFS=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
UUID=8e526587-69d7-562d-a908-a83699912a48
trap 'rm -rf -- "$TREE"' EXIT

mkdir -p /home/cenmin/coloros-build/v42
rm -f "$OUT"
test -f "$PATCHER"
rsync -aHAX --numeric-ids "$SRC"/ "$TREE"/

echo '== preflight ownership/xattr =='
stat -c 'logd mode=%a uid=%u gid=%g' "$TREE/system/bin/logd"
getfattr -d -m - "$TREE/system/bin/surfaceflinger" 2>&1 | tail -2
if [ "$(stat -c %u "$TREE/system/bin/logd")" = 0 ]; then
  echo 'FATAL: logd ownership lost' >&2
  exit 1
fi

# Patch the original file, then overwrite in place so mode, owner, group and security.selinux stay intact.
python3 -I "$PATCHER" "$TREE/system/bin/surfaceflinger" "$PATCHED"
cat "$PATCHED" > "$TREE/system/bin/surfaceflinger"
rm -f "$PATCHED"
getfattr -d -m - "$TREE/system/bin/surfaceflinger" 2>&1 | tail -2

echo '== build erofs =='
"$MKFS" -zlz4 -b4096 -C65536 -U "$UUID" -L system -T 1793807531 "$OUT" "$TREE"
echo '== fsck =='
"$FSCK" "$OUT"
echo '== dump =='
dump.erofs -s "$OUT" 2>/dev/null | grep -E 'UUID|blocks|inode count|features'
dump.erofs --path /system/bin/surfaceflinger "$OUT" 2>/dev/null | head -8
sha256sum "$OUT"
echo SYSTEM_V42_BUILT
