set -u
umount /mnt/x 2>/dev/null; losetup -D 2>/dev/null; sleep 1
ROOT=/home/cenmin/v5
TREE=$ROOT/system
rm -rf $ROOT
mkdir -p $TREE /mnt/srcsys

echo "=== mount ColorOS system.img (EROFS) ==="
mount -t erofs -o loop,ro /mnt/d/gaokun-build-temp/system.img /mnt/srcsys || { echo MOUNTFAIL; exit 1; }
df -h /mnt/srcsys | tail -1
echo "file count:"; find /mnt/srcsys -xdev | wc -l

echo "=== rsync with xattrs/ACLs/hardlinks preserved ==="
time rsync -aHAX --numeric-ids /mnt/srcsys/ $TREE/
echo "rsync rc=$?"

echo "=== verify xattr preserved on a sample ==="
getfattr -d -m - $TREE/system/lib64/libEGL.so 2>&1 | head -4
getfattr -d -m - $TREE/system/bin/surfaceflinger 2>&1 | head -4

echo "=== tree size ==="
du -sh $TREE
find $TREE | wc -l

umount /mnt/srcsys; losetup -D 2>/dev/null
echo DONE