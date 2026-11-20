#!/bin/bash
set -euo pipefail

SRC=/home/cenmin/v5/parts/vendor_a_v21.img
OUT=/home/cenmin/coloros-build/v28/vendor_a_v28.img
CAP=/mnt/e/gaokun-coloros/coloros-port/scripts/v28_capture.sh
FEATURE_SRC=/mnt/e/gaokun-coloros/coloros-port/work/stock-v5/vendor-fs/etc/permissions/android.hardware.wifi.direct.xml
FEATURE_DST=/etc/permissions/android.hardware.wifi.direct.xml

cp -f "$SRC" "$OUT"
debugfs -w -R "rm /bin/gk3-capture.sh" "$OUT" >/dev/null 2>&1 || true
debugfs -w -R "write $CAP /bin/gk3-capture.sh" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /bin/gk3-capture.sh mode 0100755" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /bin/gk3-capture.sh uid 0" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /bin/gk3-capture.sh gid 2000" "$OUT" >/dev/null
debugfs -w -R "rm /etc/init/gk3-capture.rc" "$OUT" >/dev/null 2>&1 || true
debugfs -w -R "write /mnt/e/gaokun-coloros/coloros-port/scripts/gk3-capture.rc /etc/init/gk3-capture.rc" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /etc/init/gk3-capture.rc mode 0100644" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /etc/init/gk3-capture.rc uid 0" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /etc/init/gk3-capture.rc gid 0" "$OUT" >/dev/null

debugfs -w -R "rm $FEATURE_DST" "$OUT" >/dev/null 2>&1 || true
debugfs -w -R "write $FEATURE_SRC $FEATURE_DST" "$OUT" >/dev/null
debugfs -w -R "set_inode_field $FEATURE_DST mode 0100644" "$OUT" >/dev/null
debugfs -w -R "set_inode_field $FEATURE_DST uid 0" "$OUT" >/dev/null
debugfs -w -R "set_inode_field $FEATURE_DST gid 0" "$OUT" >/dev/null
debugfs -R "cat $FEATURE_DST" "$OUT" 2>/dev/null | grep -q 'android.hardware.wifi.direct'

e2fsck -fy "$OUT" >/dev/null 2>&1 || true
sha256sum "$OUT"
stat -c '%s %n' "$OUT"
echo VENDOR_V28_BUILT
