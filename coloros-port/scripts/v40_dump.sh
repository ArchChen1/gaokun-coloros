#!/system/bin/sh
# One-shot post-boot diagnostics. Invoked by init exec_background only.
mode="${1:-postboot-10}"
base=/metadata/gk3-v40
mkdir -p "$base" 2>/dev/null || exit 1
[ -e "$base/$mode.done" ] && exit 0

case "$mode" in
  postboot-10) delay=10 ;;
  postboot-30) delay=30 ;;
  postboot-60) delay=60 ;;
  bootanim) delay=2 ;;
  *) delay=10 ;;
esac
sleep "$delay"

out="$base/$mode"
{
  echo "mode=$mode"
  echo "delay=$delay"
  date
  cat /proc/uptime
  cat /proc/cmdline
  cat /proc/1/cmdline 2>/dev/null || true
  cat /proc/1/status 2>/dev/null || true
  getprop
  ps -A
  cat /proc/mounts
  cat /sys/fs/selinux/enforce 2>/dev/null || true
} > "$out-meta.txt" 2>&1

dmesg > "$out-dmesg.txt" 2>&1
timeout 12 logcat -d -b all -v threadtime > "$out-logcat.txt" 2>&1
timeout 5 logcat -d -b crash -v threadtime > "$out-crash.txt" 2>&1
ls -l /data/tombstones /data/anr /data/system/dropbox > "$out-crashdirs.txt" 2>&1
cat /proc/last_kmsg > "$out-last-kmsg.txt" 2>&1 || true
cat /sys/fs/pstore/console-ramoops-0 > "$out-pstore.txt" 2>&1 || true

echo "probe=$mode done" > "$base/$mode.done"
sync