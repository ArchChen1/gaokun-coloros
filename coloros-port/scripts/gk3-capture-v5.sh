#!/vendor/bin/sh
# gaokun3 diagnostic capture (v5) - bounded, restart-safe
PATH=/system/bin:/vendor/bin
export PATH
LOG=/metadata/gk3-debug
mkdir -p "$LOG" 2>/dev/null
chmod 0777 "$LOG" 2>/dev/null

# keep the previous boot's files instead of deleting them
for f in logcat.txt kmsg.log snapshot.txt; do
  [ -s "$LOG/$f" ] && mv -f "$LOG/$f" "$LOG/$f.prev" 2>/dev/null
done

{
  echo "=== gk3 capture v5 start ==="
  date 2>/dev/null
  echo "--- cmdline ---"
  cat /proc/cmdline 2>/dev/null
  echo "--- mounts ---"
  cat /proc/mounts 2>/dev/null
  echo "--- getprop ---"
  getprop 2>/dev/null
} > "$LOG/snapshot.txt" 2>&1

# kernel log: bounded rewrite every 3s, starts immediately
(
  while :; do
    dmesg > "$LOG/kmsg.tmp" 2>/dev/null && mv -f "$LOG/kmsg.tmp" "$LOG/kmsg.log" 2>/dev/null
    sleep 3
  done
) &

# logcat: wait for /system, then stream with rotation
(
  i=0
  while [ "$i" -lt 1200 ]; do
    [ -x /system/bin/logcat ] && break
    sleep 0.5
    i=$((i+1))
  done
  exec /system/bin/logcat -b all -v threadtime -r 2048 -n 3 -f "$LOG/logcat.txt"
) &

# periodic service/process snapshot
(
  i=0
  while [ "$i" -lt 12 ]; do
    sleep 15
    {
      echo "=== state $i ==="
      date 2>/dev/null
      echo "--- surfaceflinger logcat ---"
      logcat -d -v threadtime 2>/dev/null | grep -iE 'surfaceflinger|drmhwc|composer|libEGL|EGL_|angle|vulkan|gralloc' | tail -300
      echo "--- init service states ---"
      getprop 2>/dev/null | grep -iE 'init.svc.(surfaceflinger|zygote|bootanim|hwcomposer|vendor.hwcomposer)'
      echo "--- ps ---"
      ps -AZ 2>/dev/null | grep -iE 'surfaceflinger|zygote|system_server|hwcomposer|composer'
    } > "$LOG/state.tmp" 2>&1
    mv -f "$LOG/state.tmp" "$LOG/snapshot.txt" 2>/dev/null
    i=$((i+1))
  done
) &

wait