#!/bin/bash
set -euo pipefail
SRC=/home/cenmin/v5/system-v5b.erofs
OUT=/home/cenmin/v5/system-v25.erofs
TREE=/home/cenmin/v25-system/tree
MKFS=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
LOG=/home/cenmin/v25-system/mkfs.log
grep -q '^ro.adb.secure=0$' "$TREE/system/build.prop"
rm -f "$OUT"
"$MKFS" -zlz4 -b4096 -C1048576 -L system -T1793346620 -U2f2ea3d1-c76b-5f2c-b99b-45ba6421cc21 "$OUT" "$TREE" >"$LOG" 2>&1
"$FSCK" "$OUT"
stat -c '%s %n' "$OUT"
sha256sum "$OUT"
echo SYSTEM_V25_BUILT