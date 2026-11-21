#!/bin/bash
set -euo pipefail

SRC=/home/cenmin/v25-system/tree
ROOT=/home/cenmin/v37-system
TREE=$ROOT/tree
OUT=/home/cenmin/coloros-build/v37/system-v37.erofs
MKFS=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
LOG=$ROOT/mkfs.log
PROP=$TREE/system/build.prop

mkdir -p "$ROOT" /home/cenmin/coloros-build/v37
rm -rf "$TREE"
mkdir -p "$TREE"
rsync -aHAX --numeric-ids "$SRC"/ "$TREE"/

python3 - "$PROP" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
data = p.read_bytes()
old = b'persist.debug.wfd.enable=1\n'
new = b'persist.debug.wfd.enable=0\n'
if data.count(old) != 1:
    raise SystemExit(f'expected exactly one WFD line, found {data.count(old)}')
with p.open('r+b') as f:
    off = data.index(old)
    f.seek(off)
    f.write(new)
    f.truncate()
print('patched', p)
PY

grep -q '^persist.debug.wfd.enable=0$' "$PROP"
! grep -q '^persist.debug.wfd.enable=1$' "$PROP"
test "$(stat -c %u "$PROP")" = 0
test "$(stat -c %g "$PROP")" = 0
test "$(stat -c %a "$PROP")" = 600
test "$(stat -c %u "$TREE/system/bin/logd")" = 1036
test "$(stat -c %g "$TREE/system/bin/logd")" = 1036
test "$(stat -c %a "$TREE/system/bin/logd")" = 550

rm -f "$OUT" "$LOG"
"$MKFS" -zlz4 -b4096 -C1048576 -L system -T1793346620 -U2f2ea3d1-c76b-5f2c-b99b-45ba6421cc21 "$OUT" "$TREE" >"$LOG" 2>&1
"$FSCK" "$OUT"

echo '--- build.prop ---'
grep -n '^persist.debug.wfd.enable=' "$PROP"
echo '--- logd in image ---'
dump.erofs --path /system/bin/logd "$OUT" 2>/dev/null | grep -E 'Uid|Gid|Access'
echo '--- image ---'
stat -c '%s %n' "$OUT"
sha256sum "$OUT"
echo SYSTEM_V37_BUILT