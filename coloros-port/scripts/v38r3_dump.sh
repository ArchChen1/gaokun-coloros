#!/system/bin/sh
# One-shot boot-loop probe. Invoked by init exec_background, never as a service.
mode="${1:-zygote}"
base=/metadata/gk3-v38r3
mkdir -p "$base" 2>/dev/null || exit 1
[ -e "$base/$mode.done" ] && exit 0

case "$mode" in
  zygote-early) delay=5 ;;
  zygote-late) delay=25 ;;
  bootanim) delay=2 ;;
  *) delay=5 ;;
esac
sleep "$delay"

out="$base/$mode"
{
  echo "mode=$mode"
  echo "delay=$delay"
  date
  cat /proc/uptime
  cat /proc/cmdline
  getprop
  ps -A
  cat /proc/mounts
  cat /sys/fs/selinux/enforce 2>/dev/null || true
} > "$out-meta.txt" 2>&1

dmesg > "$out-dmesg.txt" 2>&1
timeout 12 logcat -d -b all -v threadtime > "$out-logcat.txt" 2>&1
timeout 5 logcat -d -b crash -v threadtime > "$out-crash.txt" 2>&1
ls -l /dev/usb-ffs /sys/class/udc /sys/class/usb_role > "$out-usb.txt" 2>&1
ls -l /data/tombstones /data/anr /data/system/dropbox > "$out-crashdirs.txt" 2>&1

echo "probe=$mode done" > "$base/$mode.done"
sync