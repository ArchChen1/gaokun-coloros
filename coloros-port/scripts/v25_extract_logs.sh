#!/bin/bash
set -euo pipefail
D=/mnt/e/gaokun-coloros/coloros-port/reports/v25run
O="$D/out"
mkdir -p "$O"
set +e
e2fsck -fy "$D/metadata.img" >"$D/e2fsck.log" 2>&1
rc=$?
set -e
echo "E2FSCK_RC=$rc"
[ "$rc" -le 1 ] || { tail -80 "$D/e2fsck.log"; exit 1; }
debugfs -R "ls -l /gk3-debug" "$D/metadata.img" 2>/dev/null | tee "$D/debugfs-list.txt"
for f in capture-status.txt kmsg.log logcat.txt logcat.txt.1 logcat.txt.2 threads.txt; do
  debugfs -R "dump /gk3-debug/$f $O/$f" "$D/metadata.img" >/dev/null 2>&1 || true
done
ls -lh "$O"
echo "=== waits ==="
for o in "$O"/logcat.txt*; do
  [ -f "$o" ] || continue
  echo "--- $o"
  awk '/Waited one second/ {sub(/^.*Waited one second for /,""); sub(/ .*/,""); print}' "$o" | sort | uniq -c | sort -nr | head -25 || true
done
echo "=== engineer refs ==="
grep -a -n engineer.IEngineer "$O"/logcat* 2>/dev/null | tail -30 || true
echo "=== watchdog ==="
grep -a -n -E 'pre_watchdog|WATCHDOG KILLING|Blocked in handler' "$O"/logcat* 2>/dev/null | tail -50 || true
echo "=== status ==="
cat "$O/capture-status.txt" 2>/dev/null || true