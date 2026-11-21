#!/bin/bash
set -euo pipefail

ROOT=/home/cenmin/v37-system
TREE=$ROOT/tree
VERIFY=$ROOT/verify
SYS=/home/cenmin/coloros-build/v37/system-v37.erofs
V=/home/cenmin/coloros-build/v37/vendor_a_v37.img
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs

echo '=== tree delta vs v25 (build.prop excluded) ==='
diff -qr --no-dereference --exclude=build.prop /home/cenmin/v25-system/tree "$TREE"

echo '=== v37 build.prop in tree ==='
grep -n '^persist.debug.wfd.enable=' "$TREE/system/build.prop"
test "$(stat -c %a "$TREE/system/build.prop")" = 600
test "$(stat -c %u "$TREE/system/build.prop")" = 0
test "$(stat -c %g "$TREE/system/build.prop")" = 0

echo '=== extract and check system image ==='
rm -rf "$VERIFY"
mkdir -p "$VERIFY"
"$FSCK" --extract="$VERIFY" --no-preserve "$SYS" >/dev/null 2>&1
grep -n '^persist.debug.wfd.enable=' "$VERIFY/system/build.prop"
test "$(grep -c '^persist.debug.wfd.enable=0$' "$VERIFY/system/build.prop")" = 1
! grep -q '^persist.debug.wfd.enable=1$' "$VERIFY/system/build.prop"
dump.erofs --path /system/build.prop "$SYS" 2>/dev/null | grep -E 'Size:|Uid:|Gid:|Access:'
dump.erofs --path /system/bin/logd "$SYS" 2>/dev/null | grep -E 'Uid:|Gid:|Access:'

echo '=== vendor checks ==='
debugfs -R "cat /etc/init/hw/init.gaokun3.rc" "$V" 2>/dev/null | tail -10
debugfs -R "cat /etc/init/hw/init.gaokun3.rc" "$V" 2>/dev/null | grep -q 'setprop persist.debug.wfd.enable 0'
if debugfs -R "stat /etc/permissions/android.hardware.wifi.direct.xml" "$V" 2>&1 | grep -q 'Inode:'; then
  echo 'Wi-Fi Direct feature still present' >&2
  exit 1
fi
e2fsck -fn "$V"

echo '=== image metadata ==='
stat -c '%s %n' "$SYS" "$V" /home/cenmin/coloros-build/super-coloros-v37.simg 2>/dev/null || true
sha256sum "$SYS" "$V"
echo V37_VERIFY_OK