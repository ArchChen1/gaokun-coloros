#!/bin/bash
set -euo pipefail

V=/home/cenmin/coloros-build/v28/vendor_a_v28.img
OUT=/tmp/android.hardware.wifi.direct.xml

debugfs -R "dump /etc/permissions/android.hardware.wifi.direct.xml $OUT" "$V" >/dev/null 2>&1
grep -q 'android.hardware.wifi.direct' "$OUT"
debugfs -R "cat /bin/gk3-capture.sh" "$V" 2>/dev/null | grep -q 'gk3-debug'
debugfs -R "cat /etc/init/gk3-capture.rc" "$V" 2>/dev/null | grep -q 'post-fs-data'
echo VENDOR_V28_CHECK_OK
sha256sum "$V"
stat -c '%s %n' "$V"
