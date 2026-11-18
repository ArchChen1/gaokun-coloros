#!/bin/bash
set -euo pipefail
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
S=/home/cenmin/coloros-build/super-coloros-v5b.simg
V=/home/cenmin/v5verify
P=/home/cenmin/v5/parts
SYS=/home/cenmin/v5/system-v5b.erofs
rm -rf "$V/b"
mkdir -p "$V/b"
echo "=== unsparse + unpack ==="
"$OT/simg2img" "$S" "$V/b/super.raw" 2>/dev/null
"$OT/lpunpack" "$V/b/super.raw" "$V/b" >/dev/null 2>&1
echo "=== verify system_a == new build ==="
sha256sum "$V/b/system_a.img" "$SYS"
echo "=== verify vendor_a unchanged ==="
sha256sum "$V/b/vendor_a.img" "$P/vendor_a.img"
echo
echo "=== CRITICAL: ownership in shipped system_a ==="
for f in /system/bin/logd /system/bin/surfaceflinger /system/bin/init; do
  printf '%-30s ' "$f"
  dump.erofs --path "$f" "$V/b/system_a.img" 2>/dev/null | grep -E 'Uid|Access' | tr '\n' ' '
  echo
done
echo
echo "=== graphics libs still crDroid version ==="
for f in libEGL.so libGLESv2_angle.so libvulkan.so; do
  printf '  %-24s ' "$f"
  dump.erofs --path "/system/lib64/$f" "$V/b/system_a.img" 2>/dev/null | grep 'Size:' | head -1
done
echo "=== kgsl refs in libEGL (want 0) ==="
X=/home/cenmin/v5/verify_x
rm -rf "$X"; mkdir -p "$X"
fsck.erofs --extract="$X" --no-preserve "$V/b/system_a.img" >/dev/null 2>&1 || true
strings -a "$X/system/lib64/libEGL.so" 2>/dev/null | grep -c 'kgsl-3d0' || echo 0
echo
echo "=== unchanged partitions same as before ==="
for n in system_ext product odm my_product my_stock my_manifest my_region my_engineering my_heytap my_carrier my_bigball; do
  a=$(sha256sum "$V/b/${n}_a.img" 2>/dev/null | cut -c1-12)
  b=$(sha256sum "$P/${n}_a.img" 2>/dev/null | cut -c1-12)
  [ "$a" = "$b" ] && echo "  SAME $n $a" || echo "  DIFF $n $a vs $b"
done
echo
echo "=== sparse file size / erase block ==="
ls -l "$S"
"$OT/simg2img" -c "$S" /dev/null 2>&1 | head -2 || true
rm -f "$V/b/super.raw"
echo VERIFIED