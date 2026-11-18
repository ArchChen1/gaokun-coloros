set -u
umount /mnt/x 2>/dev/null; losetup -D 2>/dev/null; sleep 1
ROOT=/home/cenmin/v5
TREE=$ROOT/system
OUT=$ROOT/system-v5.erofs
rm -f $OUT

echo "########## original UUID / features ##########"
dump.erofs -s /mnt/d/gaokun-build-temp/system.img 2>&1 | grep -E 'UUID|features|blocks'
echo

echo "########## build erofs (lz4, 4096 block, keep UUID) ##########"
time mkfs.erofs \
  -zlz4 \
  -b4096 \
  -C65536 \
  -U 8e526587-69d7-562d-a908-a83699912a48 \
  -L system \
  -T 1793807531 \
  --all-root \
  "$OUT" "$TREE" 2>&1 | tail -20

echo
echo "########## verify ##########"
ls -l "$OUT"
dump.erofs -s "$OUT" 2>&1 | grep -E 'UUID|features|blocks|inode count'
echo "--- fsck ---"
fsck.erofs "$OUT" 2>&1 | tail -5

echo
echo "########## correctness: swapped libs present in new image ##########"
mkdir -p /mnt/verify
mount -t erofs -o loop,ro "$OUT" /mnt/verify || { echo VERIFYMOUNTFAIL; exit 1; }
for f in libEGL.so libGLESv2_angle.so libvulkan.so; do
  printf '  %-22s %s\n' "$f" "$(sha256sum /mnt/verify/system/lib64/$f | cut -c1-16)"
done
echo "  -- expect libEGL=68f31523c6de83f1, angle=67227d91c875a94b, vulkan=e844578b69d4bbad"
echo "--- xattr check ---"
getfattr -d -m - /mnt/verify/system/lib64/libEGL.so 2>&1 | tail -2
echo "--- file count ---"
find /mnt/verify | wc -l
umount /mnt/verify; losetup -D 2>/dev/null
echo STAGE1_OK