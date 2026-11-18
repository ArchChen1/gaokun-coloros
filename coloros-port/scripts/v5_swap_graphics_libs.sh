set -u
ROOT=/home/cenmin/v5
TREE=$ROOT/system
SRC=/mnt/srcsys
LOS=/mnt/lossys
REPORT=$ROOT/swap-report.txt

echo "########## 0. sanity ##########"
[ -d "$TREE/system/lib64" ] || { echo "TREE MISSING"; exit 1; }
find "$TREE" | wc -l
echo "-- /system/etc/vulkan present? --"
ls -la "$TREE/system/etc/vulkan" 2>&1 | head -5
ls -la "$TREE/system/etc/vulkan/icd.d" 2>&1 | head -10

echo
echo "########## 1. mount LOS system (source of gaokun graphics stack) ##########"
umount $LOS 2>/dev/null; losetup -D 2>/dev/null; sleep 1
mkdir -p $LOS
mount -t ext4 -o loop,ro /home/cenmin/los-parts/system_a.img $LOS || { echo LOSMOUNTFAIL; exit 1; }

echo
echo "########## 2. back up ColorOS originals + swap ##########"
mkdir -p $ROOT/orig-libs
FILES="libEGL.so libGLESv1_CM.so libGLESv2.so libGLESv3.so libEGL_angle.so libGLESv1_CM_angle.so libGLESv2_angle.so libvulkan.so libegl_flags.so"
for abi in lib64 lib; do
  mkdir -p $ROOT/orig-libs/$abi
  for f in $FILES; do
    d=$TREE/system/$abi/$f
    s=$LOS/system/$abi/$f
    [ -e "$s" ] || { echo "  SKIP  $abi/$f (not in LOS)"; continue; }
    [ -e "$d" ] || { echo "  NEW   $abi/$f"; }
    if [ -e "$d" ]; then cp -a "$d" $ROOT/orig-libs/$abi/$f; fi
    cp -f "$s" "$d"
    chmod 0644 "$d"; chown 0:0 "$d"
    setfattr -n security.selinux -v "u:object_r:system_lib_file:s0" "$d" 2>/dev/null
    printf '  SWAP %-5s %-24s %8s -> %8s\n' "$abi" "$f" "$(stat -c%s $ROOT/orig-libs/$abi/$f 2>/dev/null || echo 0)" "$(stat -c%s $d)" | tee -a $REPORT
  done
done
umount $LOS; losetup -D 2>/dev/null

echo
echo "########## 3. verify swapped = LOS source ##########"
echo "  -- swapped libs now --"
for abi in lib64 lib; do for f in $FILES; do printf '  %-5s %-24s %s\n' $abi $f "$(sha256sum $TREE/system/$abi/$f 2>/dev/null | cut -c1-16)"; done; done

echo
echo "########## 4. xattr on swapped files ##########"
getfattr -d -m - $TREE/system/lib64/libEGL.so 2>&1 | tail -2
getfattr -d -m - $TREE/system/lib64/libGLESv2_angle.so 2>&1 | tail -2
echo SWAP_DONE