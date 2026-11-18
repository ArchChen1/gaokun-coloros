#!/vendor/bin/sh
# gaokun3 diagnostic capture (temporary debug build)
PATH=/system/bin:/vendor/bin
export PATH
LOG=/metadata/gk3-debug

# /metadata is mounted first-stage, but only start once it is actually visible.
grep -q ' /metadata ' /proc/mounts || exit 1
mkdir -p "$LOG" || exit 1
chmod 0777 "$LOG" 2>/dev/null
rm -f "$LOG"/kmsg.log "$LOG"/kmsg.previous.log "$LOG"/logcat.txt* "$LOG"/logcat.previous.txt* "$LOG"/snapshot.txt

{
  echo "gaokun3 metadata capture started"
  date 2>/dev/null
  echo "===== cmdline ====="
  cat /proc/cmdline
} > "$LOG/snapshot.txt"
cp "$LOG/snapshot.txt" "$LOG/kmsg.log"

# Keep a bounded kernel-log history. Writing cat /dev/kmsg continuously would
# fill the 32 MiB metadata partition because the UCSI driver logs every 200 ms.
(
  while :; do
    dmesg > "$LOG/kmsg.tmp" 2>/dev/null && mv "$LOG/kmsg.tmp" "$LOG/kmsg.log"
    sleep 5
  done
) &

# Logcat is started as soon as the binary appears. Ring-buffer rotation keeps the
# total footprint bounded while preserving the newest crash/system logs.
(
  i=0
  while [ "$i" -lt 600 ]; do
    [ -x /system/bin/logcat ] && break
    sleep 0.2
    i=$((i + 1))
  done
  exec /system/bin/logcat -b crash -b system -b main -v threadtime \
    -r 4096 -n 4 -f "$LOG/logcat.txt"
) &

# Periodic state snapshots make the zygote/system_server crash point easy to see
# even if a later, unrelated log line floods the ring.
(
  i=0
  while [ "$i" -lt 30 ]; do
    sleep 10
    {
      echo "===== snapshot $((i + 1)) $(date 2>/dev/null) ====="
      echo "--- ps -AZ ---"
      ps -AZ 2>&1
      echo "--- service list ---"
      service list 2>&1
      echo "--- crash logcat ---"
      logcat -d -b crash -v threadtime 2>&1
      echo "--- system logcat tail ---"
      logcat -d -b system -t 500 -v threadtime 2>&1
    } > "$LOG/snapshot.tmp"
    mv "$LOG/snapshot.tmp" "$LOG/snapshot.txt"
    i=$((i + 1))
  done
) &

wait