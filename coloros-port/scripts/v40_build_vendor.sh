#!/bin/bash
set -euo pipefail

V38=/home/cenmin/coloros-build/v38
SRC="$V38/vendor_a_v38r3.img"
OUT="$V38/vendor_a_v40.img"
PROBE=/mnt/e/gaokun-coloros/coloros-port/scripts/v40_dump.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

test -f "$SRC"
test -f "$PROBE"
cp -f "$SRC" "$OUT"

debugfs -R "dump /etc/init/hw/init.gaokun3.rc $TMP/init.gaokun3.rc" "$OUT" >/dev/null
cat >> "$TMP/init.gaokun3.rc" <<'EOF'

# gaokun3 v40: post-boot snapshots. bootanim=stopped is the point where the
# UI reaches 100%; capture 3/10/30/60 seconds later to catch the black-screen
# reboot. These are one-shot exec_background probes, not services.
on property:init.svc.bootanim=stopped
    write /metadata/gk3-v40-bootanim-trigger 1
    exec_background - root root -- /system/bin/sh /vendor/bin/v40_dump.sh postboot-3
    exec_background - root root -- /system/bin/sh /vendor/bin/v40_dump.sh postboot-10
    exec_background - root root -- /system/bin/sh /vendor/bin/v40_dump.sh postboot-30
    exec_background - root root -- /system/bin/sh /vendor/bin/v40_dump.sh postboot-60

on property:sys.boot_completed=1
    write /metadata/gk3-v40-boot-completed 1
EOF

debugfs -w -R "rm /bin/v40_dump.sh" "$OUT" >/dev/null 2>&1 || true
debugfs -w -R "write $PROBE /bin/v40_dump.sh" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /bin/v40_dump.sh mode 0100755" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /bin/v40_dump.sh uid 0" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /bin/v40_dump.sh gid 0" "$OUT" >/dev/null

debugfs -w -R "rm /etc/init/hw/init.gaokun3.rc" "$OUT" >/dev/null
debugfs -w -R "write $TMP/init.gaokun3.rc /etc/init/hw/init.gaokun3.rc" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /etc/init/hw/init.gaokun3.rc mode 0100644" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /etc/init/hw/init.gaokun3.rc uid 0" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /etc/init/hw/init.gaokun3.rc gid 0" "$OUT" >/dev/null

set +e
e2fsck -fy "$OUT" >"$TMP/e2fsck.log" 2>&1
FSCK_RC=$?
set -e
if [ "$FSCK_RC" -gt 1 ]; then
  cat "$TMP/e2fsck.log"
  exit "$FSCK_RC"
fi

echo '== rc tail =='
debugfs -R 'cat /etc/init/hw/init.gaokun3.rc' "$OUT" 2>/dev/null | tail -30
echo '== probe stat =='
debugfs -R 'stat /bin/v40_dump.sh' "$OUT" 2>/dev/null | head -8
sha256sum "$OUT"
echo VENDOR_V40_BUILT
