set -u
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
CB=/home/cenmin/coloros-build
OUT=$CB/super-coloros-v5.simg
V=$CB/vendor-gaokun-v5.img
SYS5=/home/cenmin/v5/system-v5.erofs
PARTS=/home/cenmin/v5/parts
VER=/home/cenmin/v5/verify

echo "########## 1. unsparse + unpack ##########"
rm -rf $VER; mkdir -p $VER
$OT/simg2img "$OUT" $VER/super.raw
$OT/lpunpack $VER/super.raw $VER 2>&1 | tail -3
ls -l $VER/*.img

echo
echo "########## 2. verify: changed partitions match new sources ##########"
echo "-- system_a (want == $SYS5) --"
sha256sum $VER/system_a.img $SYS5
echo "-- vendor_a (want == $V) --"
sha256sum $VER/vendor_a.img $V

echo
echo "########## 3. verify: unchanged partitions identical to v4c ##########"
for n in system_ext product odm my_product my_stock my_manifest my_region my_engineering my_heytap my_carrier my_bigball; do
  a=$(sha256sum $VER/${n}_a.img | cut -c1-16)
  b=$(sha256sum $PARTS/${n}_a.img | cut -c1-16)
  [ "$a" = "$b" ] && s=SAME || s=DIFF
  printf '  %-6s %-16s %s\n' "$s" "$n" "$a"
done

echo
echo "########## 4. verify: swapped graphics libs inside super's system_a ##########"
mkdir -p /mnt/v
mount -t erofs -o loop,ro $VER/system_a.img /mnt/v
for f in libEGL.so libGLESv1_CM.so libGLESv2.so libGLESv3.so libEGL_angle.so libGLESv1_CM_angle.so libGLESv2_angle.so libvulkan.so libegl_flags.so; do
  printf '  %-24s %s\n' "$f" "$(sha256sum /mnt/v/system/lib64/$f | cut -c1-16)"
done
echo "  -- expect libEGL=68f31523c6de83f1, libEGL_angle=4445090c72f01229, libvulkan=e844578b69d4bbad --"
echo "  -- kgsl references in libEGL (want 0) --"
strings -a /mnt/v/system/lib64/libEGL.so | grep -c 'kgsl-3d0' || true
echo "  -- capture script present in vendor? --"
umount /mnt/v; losetup -D 2>/dev/null; sleep 1
mount -o loop,ro $VER/vendor_a.img /mnt/v
debugfs -R "stat /bin/gk3-capture.sh" $VER/vendor_a.img 2>&1 | grep -E 'Inode:|File not found'
debugfs -R "dump /bin/gk3-capture.sh /tmp/c5" $VER/vendor_a.img >/dev/null 2>&1
sha256sum /tmp/c5
umount /mnt/v; losetup -D 2>/dev/null
echo
echo "########## 5. group budget check ##########"
echo "-- partition total vs group limit --"
python3 - <<'PY'
import os
p='/home/cenmin/v5/verify'
tot=0
for f in sorted(os.listdir(p)):
    if f.endswith('_a.img'):
        s=os.path.getsize(os.path.join(p,f))
        tot+=s
        print(f"  {f:28s} {s:>13,}")
print(f"  {'TOTAL':28s} {tot:>13,}")
lim=12683575296
print(f"  {'GROUP LIMIT':28s} {lim:>13,}")
print(f"  {'HEADROOM':28s} {lim-tot:>13,}  ({(lim-tot)/1024/1024:.1f} MiB)")
PY
rm -f $VER/super.raw
echo SUPER_V5_VERIFIED