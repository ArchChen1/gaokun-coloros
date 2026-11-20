#!/vendor/bin/sh
# gaokun3 ColorOS diagnostic capture v28
PATH=/system/bin:/vendor/bin
export PATH
LOG=/metadata/gk3-debug

i=0
while [ "$i" -lt 240 ]; do
  grep -q " /metadata " /proc/mounts && break
  sleep 0.5
  i=$((i+1))
done
grep -q " /metadata " /proc/mounts || exit 1
mkdir -p "$LOG" 2>/dev/null
chmod 0777 "$LOG" 2>/dev/null
rm -f "$LOG"/*.tmp 2>/dev/null

{
  echo "start $(date 2>/dev/null)"
  echo "--- cmdline ---"; cat /proc/cmdline 2>/dev/null
  echo "--- boot props ---"; getprop 2>/dev/null | grep -E "ro.build|ro.product|ro.boot|ro.adb|selinux"
  echo "--- feature wifi.direct ---"; dumpsys package 2>/dev/null | grep -m2 -E "android.hardware.wifi.direct" || true
  echo "--- pid system_server ---"; pidof system_server 2>/dev/null
} > "$LOG/capture-status.txt"

(while :; do dmesg > "$LOG/kmsg.tmp" 2>/dev/null && mv -f "$LOG/kmsg.tmp" "$LOG/kmsg.log" 2>/dev/null; sleep 2; done) &
(
  i=0
  while [ "$i" -lt 1200 ]; do [ -x /system/bin/logcat ] && break; sleep 0.5; i=$((i+1)); done
  exec /system/bin/logcat -b all -v threadtime -r 8192 -n 4 -f "$LOG/logcat.txt"
) &

(
  last_pid=
  n=0
  while [ "$n" -lt 300 ]; do
    n=$((n+1))
    p=$(pidof system_server 2>/dev/null | awk '{print $1}')
    if [ -n "$p" ]; then
      if [ "$p" != "$last_pid" ]; then
        {
          echo "===== SYSTEM_SERVER PID $p $(date 2>/dev/null) ====="
          cat "/proc/$p/status" 2>/dev/null
        } >> "$LOG/system-server.txt" 2>&1
        last_pid=$p
      fi
      if [ $((n % 10)) -eq 0 ]; then
        {
          echo "===== SAMPLE pid=$p time=$(date 2>/dev/null) ====="
          cat "/proc/$p/task/$p/wchan" 2>/dev/null; echo
          cat "/proc/$p/task/$p/stack" 2>/dev/null; echo
        } >> "$LOG/system-server.txt" 2>&1
      fi
      if [ $((n % 15)) -eq 0 ]; then kill -3 "$p" 2>/dev/null; fi
    fi
    sleep 1
  done
) &
wait
