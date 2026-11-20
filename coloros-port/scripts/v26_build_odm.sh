#!/bin/bash
set -euo pipefail
SRC=/home/cenmin/v5/parts/odm_v24_a.img
WORK=/home/cenmin/v26-odm
OUT=/home/cenmin/v5/parts/odm_v26_a.img
MKFS=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
rm -rf "$WORK"
mkdir -p "$WORK/mnt" "$WORK/tree"
mount -t erofs -o loop,ro "$SRC" "$WORK/mnt"
cp -a "$WORK/mnt/." "$WORK/tree/"
umount "$WORK/mnt"
rm -f "$WORK/tree/etc/vintf/manifest/android.hardware.contexthub-service.qmi.xml"
rm -f "$WORK/tree/etc/init/android.hardware.contexthub-service.qmi.rc"
if grep -R -a -l 'IContextHub/default' "$WORK/tree/etc/vintf" "$WORK/tree/etc/init" 2>/dev/null | grep -q .; then
  echo 'unexpected contexthub declaration remains' >&2
  exit 2
fi
rm -f "$OUT"
"$MKFS" -zlz4 -b4096 -C1048576 -L odm -T1793346620 -U2f2ea3d1-c76b-5f2c-b99b-45ba6421cc21 "$OUT" "$WORK/tree" >"$WORK/mkfs.log" 2>&1
"$FSCK" "$OUT"
sha256sum "$OUT"
stat -c '%s %n' "$OUT"
echo ODM_V26_BUILT