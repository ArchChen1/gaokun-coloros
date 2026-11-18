#!/vendor/bin/sh
# gaokun3 diagnostic capture (temporary debug build)
PATH=/system/bin:/vendor/bin
export PATH
ESP=/mnt/gk3esp
LOG=$ESP/gk3-debug
mkdir -p "$ESP"
mkdir -p "$LOG"

mount_esp() {
  if [ -e /dev/block/by-name/esp ]; then
    mount -t vfat -o rw,umask=000 /dev/block/by-name/esp "$ESP" 2>/dev/null && return 0
  fi
  DEVNUM=$(cat /sys/class/block/nvme0n1p1/dev 2>/dev/null)
  [ -n "$DEVNUM" ] || return 1
  MAJ=${DEVNUM%:*}
  MIN=${DEVNUM#*:}
  [ -e /dev/nvme0n1p1 ] || mknod /dev/nvme0n1p1 b "$MAJ" "$MIN" 2>/dev/null
  mount -t vfat -o rw,umask=000 /dev/nvme0n1p1 "$ESP" 2>/dev/null
}

i=0
while [ $i -lt 120 ]; do
  if mount_esp; then break; fi
  sleep 1
  i=$((i+1))
done
if ! mountpoint -q "$ESP" 2>/dev/null; then
  mkdir -p /data/vendor/gk3-debug
  echo "ESP mount failed" > /data/vendor/gk3-debug/capture.error
  exit 1
fi

mkdir -p "$LOG"
rm -f "$LOG/logcat.previous.txt" "$LOG/kmsg.previous.log"
[ -f "$LOG/logcat.txt" ] && mv "$LOG/logcat.txt" "$LOG/logcat.previous.txt"
[ -f "$LOG/kmsg.log" ] && mv "$LOG/kmsg.log" "$LOG/kmsg.previous.log"

echo "gaokun3 capture started" > "$LOG/kmsg.log"
cat /proc/cmdline >> "$LOG/kmsg.log"
echo "===== kmsg =====" >> "$LOG/kmsg.log"
( cat /dev/kmsg >> "$LOG/kmsg.log" 2>&1 ) &
( logcat -b all -v threadtime -f "$LOG/logcat.txt" ) &
wait