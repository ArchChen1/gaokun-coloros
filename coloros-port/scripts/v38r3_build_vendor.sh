#!/bin/bash
set -euo pipefail

V38=/home/cenmin/coloros-build/v38
SRC="$V38/vendor_a_v38r2.img"
OUT="$V38/vendor_a_v38r3.img"
PROBE=/mnt/e/gaokun-coloros/coloros-port/scripts/v38r3_dump.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

test -f "$SRC"
test -f "$PROBE"
cp -f "$SRC" "$OUT"

# Pull the existing ColorOS/gaokun rc, append one-shot diagnostics.
debugfs -R "dump /etc/init/hw/init.gaokun3.rc $TMP/init.gaokun3.rc" "$OUT" >/dev/null
cat >> "$TMP/init.gaokun3.rc" <<'EOF'

# gaokun3 v38r3: one-shot diagnostics for the zygote/system_server restart loop.
# exec_background is intentional: init does not wait for these probes and no
# persistent service or polling loop is installed.
on property:init.svc.zygote=running
    write /metadata/gk3-v38r3-zygote-trigger 1
    exec_background - root root -- /system/bin/sh /vendor/bin/v38r3_dump.sh zygote-early
    exec_background - root root -- /system/bin/sh /vendor/bin/v38r3_dump.sh zygote-late

on property:init.svc.bootanim=stopped
    write /metadata/gk3-v38r3-bootanim-trigger 1
    exec_background - root root -- /system/bin/sh /vendor/bin/v38r3_dump.sh bootanim

on property:sys.boot_completed=1
    write /metadata/gk3-v38r3-boot-completed 1
EOF

# Install the probe as a readable vendor file. It is executed through
# /system/bin/sh, so no new executable SELinux domain transition is needed.
debugfs -w -R "rm /bin/v38r3_dump.sh" "$OUT" >/dev/null 2>&1 || true
debugfs -w -R "write $PROBE /bin/v38r3_dump.sh" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /bin/v38r3_dump.sh mode 0100755" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /bin/v38r3_dump.sh uid 0" "$OUT" >/dev/null
debugfs -w -R "set_inode_field /bin/v38r3_dump.sh gid 0" "$OUT" >/dev/null

# Replace the rc atomically at the image level.
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
debugfs -R 'cat /etc/init/hw/init.gaokun3.rc' "$OUT" 2>/dev/null | tail -24
echo '== probe stat =='
debugfs -R 'stat /bin/v38r3_dump.sh' "$OUT" 2>/dev/null | head -8
echo '== probe tail =='
debugfs -R 'cat /bin/v38r3_dump.sh' "$OUT" 2>/dev/null | tail -8
sha256sum "$OUT"
echo VENDOR_V38R3_BUILT