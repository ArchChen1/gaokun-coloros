#!/bin/bash
set -euo pipefail

V38=/home/cenmin/coloros-build/v38
SRC="$V38/vendor_a_v40.img"
OUT="$V38/vendor_a_v41.img"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

test -f "$SRC"
cp -f "$SRC" "$OUT"

debugfs -R "dump /etc/init/hw/init.gaokun3.rc $TMP/init.gaokun3.rc" "$OUT" >/dev/null
cat >> "$TMP/init.gaokun3.rc" <<'EOF'

# gaokun3 v41: HyperOS-proven SurfaceFlinger policy for mainline drm_hwcomposer.
# ColorOS defaults enable HWC virtual display surfaces and do not latch
# unsignaled frames; on this device that produces repeated
# "trackPendingFrame: Invalid present fence" and invalid HWUI surfaces.
on post-fs-data
    setprop debug.sf.enable_hwc_vds 0
    setprop debug.sf.latch_unsignaled 1
    setprop debug.sf.disable_backpressure 1
    setprop debug.sf.set_idle_timer_ms 1000000
    setprop debug.sf.set_touch_timer_ms 1000000
    setprop debug.sf.enable_frame_rate_override false
    setprop persist.sys.background_blur_supported false
    setprop log.tag.drmhwc E
EOF

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
debugfs -R 'cat /etc/init/hw/init.gaokun3.rc' "$OUT" 2>/dev/null | tail -22
sha256sum "$OUT"
echo VENDOR_V41_BUILT