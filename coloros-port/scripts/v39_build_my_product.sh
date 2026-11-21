#!/bin/bash
set -euo pipefail

BASE=/home/cenmin/v5/parts/my_product_a.img
OUTDIR=/home/cenmin/coloros-build/v39
OUT="$OUTDIR/my_product_a_v39.img"
TREE=$(mktemp -d /home/cenmin/v39-myproduct-tree.XXXXXX)
CHECK=/mnt/v39-myprod-check
SRC_MNT=/mnt/v39-myprod-src
MKFS=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
UUID=d133458d-0e5d-58f3-b521-b1bedbb17daf
FEATURE=/etc/permissions/oplus.features.connectivity.xml

mkdir -p "$OUTDIR" "$CHECK" "$SRC_MNT"
umount "$CHECK" 2>/dev/null || true
umount "$SRC_MNT" 2>/dev/null || true
rm -f "$OUT"

echo "== copy base my_product with xattrs =="
mount -t erofs -o loop,ro "$BASE" "$SRC_MNT"
rsync -aAXH --numeric-ids "$SRC_MNT"/ "$TREE"/
umount "$SRC_MNT"

python3 - "$TREE$FEATURE" <<'PY'
import pathlib
import sys
p = pathlib.Path(sys.argv[1])
with p.open('r+', encoding='utf-8') as f:
    text = f.read()
    needle = '    <oplus-feature name="oplus.software.wlan.smart_antenna" />\n'
    if text.count(needle) != 1:
        raise SystemExit(f'unexpected smart_antenna declaration count: {text.count(needle)}')
    text = text.replace(needle, '')
    f.seek(0)
    f.write(text)
    f.truncate()
PY

echo "== build erofs (lz4, preserve ownership/xattrs) =="
"$MKFS" -zlz4 -b4096 -C65536 -U "$UUID" -L my_product -T 1793807531 "$OUT" "$TREE"

echo "== fsck =="
"$FSCK" "$OUT"

echo "== readback feature check =="
mount -t erofs -o loop,ro "$OUT" "$CHECK"
if grep -q 'oplus.software.wlan.smart_antenna' "$CHECK$FEATURE"; then
  echo 'smart_antenna still present' >&2
  umount "$CHECK"
  exit 1
fi
grep -n -i -C2 'smart_antenna' "$CHECK$FEATURE" || true
umount "$CHECK"

echo "== stat =="
dump.erofs --path "$FEATURE" "$OUT" 2>/dev/null | head -10
if ! dump.erofs --path "$FEATURE" "$OUT" 2>/dev/null | grep -q 'Xattr size: 16'; then echo 'feature xattr missing' >&2; exit 1; fi
sha256sum "$OUT"
echo "TREE=$TREE"
echo MY_PRODUCT_V39_BUILT
