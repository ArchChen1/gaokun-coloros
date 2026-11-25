#!/system/bin/sh
LOG=/metadata
dump() {
  tag=$1
  /system/bin/dmesg > $LOG/gk3-dmesg-$tag.txt 2>&1
  /system/bin/logcat -d -v threadtime -t 3000 -b main,system,crash > $LOG/gk3-logcat-$tag.txt 2>&1
  /system/bin/getprop > $LOG/gk3-props-$tag.txt 2>&1
  /system/bin/ps -A > $LOG/gk3-ps-$tag.txt 2>&1
  /system/bin/dumpsys SurfaceFlinger --list > $LOG/gk3-sf-$tag.txt 2>&1
  /system/bin/dumpsys window > $LOG/gk3-window-$tag.txt 2>&1
}
sleep 20; dump a
sleep 25; dump b
sleep 30; dump c
cp -f /data/tombstones/tombstone_0* $LOG/ 2>/dev/null || true
cp -f /data/anr/anr_* $LOG/ 2>/dev/null || true
ls -l $LOG > $LOG/gk3-ls.txt 2>&1
