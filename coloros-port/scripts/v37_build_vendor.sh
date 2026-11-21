#!/bin/bash
set -euo pipefail

SRC=/home/cenmin/coloros-build/v36/vendor_a_v36.img
OUT=/home/cenmin/coloros-build/v37/vendor_a_v37.img
RC=/tmp/init.gaokun3.v37.rc
FEATURE=/etc/permissions/android.hardware.wifi.direct.xml

mkdir -p /home/cenmin/coloros-build/v37
cp -f "$SRC" "$OUT"
debugfs -R "dump /etc/init/hw/init.gaokun3.rc $RC" "$OUT" >/dev/null 2>&1

python3 - "$RC" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding='utf-8')
needle = 'setprop persist.debug.wfd.enable 0'
if needle not in s:
    s = s.rstrip() + '''

# gaokun3 v37: override any persisted WFD value before zygote starts.
on post-fs-data
    setprop persist.debug.wfd.enable 0
'''
p.write_text(s, encoding='utf-8')
print('patched', p)
PY

debugfs -w -R "rm $FEATURE" "$OUT" >/dev/null 2>&1 || true
debugfs -w -R "rm /etc/init/hw/init.gaokun3.rc" "$OUT" >/dev/null 2>&1 || true
debugfs -w -R "write $RC /etc/init/hw/init.gaokun3.rc" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /etc/init/hw/init.gaokun3.rc mode 0100644" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /etc/init/hw/init.gaokun3.rc uid 0" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /etc/init/hw/init.gaokun3.rc gid 0" "$OUT" >/dev/null

if debugfs -R "stat $FEATURE" "$OUT" 2>&1 | grep -q 'Inode:'; then
  echo "Wi-Fi Direct feature still present" >&2
  exit 1
fi
debugfs -R "cat /etc/init/hw/init.gaokun3.rc" "$OUT" 2>/dev/null | grep -q 'setprop persist.debug.wfd.enable 0'
e2fsck -fy "$OUT" >/dev/null 2>&1 || true

echo '--- init tail ---'
debugfs -R "cat /etc/init/hw/init.gaokun3.rc" "$OUT" 2>/dev/null | tail -12
echo '--- wifi.direct stat ---'
debugfs -R "stat $FEATURE" "$OUT" 2>&1 | head -3 || true
echo '--- vendor ---'
stat -c '%s %n' "$OUT"
sha256sum "$OUT"
echo VENDOR_V37_BUILT