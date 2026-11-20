#!/bin/bash
set -u
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
S=/home/cenmin/coloros-build/super-coloros-v23.simg
V=/home/cenmin/v23verify
P=/home/cenmin/v5/parts
mkdir -p "$V"
rm -f "$V"/*.img
"$OT/simg2img" "$S" "$V/raw.img" || { echo UNSPARSE_FAIL; exit 1; }
"$OT/lpunpack" "$V/raw.img" "$V" >/dev/null 2>&1 || { echo UNPACK_FAIL; exit 1; }
rm -f "$V/raw.img"

echo "=== system_a 与源一致 ==="
sha256sum "$V/system_a.img" /home/cenmin/v5/system-v5b.erofs

echo "=== vendor_a 与注入源一致 ==="
sha256sum "$V/vendor_a.img" "$P/vendor_a_v21.img"

echo "=== stub 在镜像里且 SHA 一致 ==="
debugfs -R "dump /bin/hw/mixlut3d_stub /tmp/s14.out" "$V/vendor_a.img" >/dev/null 2>&1
sha256sum /tmp/s14.out /home/cenmin/ra-work/mixlut3d_stub
file /tmp/s14.out
stat -c '%a %u %g %s' /tmp/s14.out

echo "=== rc 内容 ==="
debugfs -R "cat /etc/init/mixlut3d-stub.rc" "$V/vendor_a.img" 2>/dev/null

echo "=== 确认 VINTF 没有 mixlut 文件 ==="
debugfs -R "ls /etc/vintf/manifest" "$V/vendor_a.img" 2>/dev/null | tr ' ' '\n' | grep -i mixlut || echo NO_MIXLUT_VINTF
debugfs -R "dump /etc/vintf/manifest.xml /tmp/m14v" "$V/vendor_a.img" >/dev/null 2>&1
sha256sum /tmp/m14v
echo "期望原版: dd35a17d5e06d41e1b3d9354e26cced96de6ee5cf988a7f892adfe163cd7bf7c"

echo "=== file_contexts ==="
debugfs -R "dump /etc/selinux/vendor_file_contexts /tmp/f14v" "$V/vendor_a.img" >/dev/null 2>&1
grep -c mixlut3d_stub /tmp/f14v
tail -2 /tmp/f14v

echo "=== logd 属主 ==="
dump.erofs --path /system/bin/logd "$V/system_a.img" 2>/dev/null | grep -E 'Uid|Access' || true

echo "=== 其它分区 SAME/DIFF ==="
for n in system_ext product odm my_product my_stock my_manifest my_region my_engineering my_heytap my_carrier my_bigball; do
  a=$(sha256sum "$V/${n}_a.img" 2>/dev/null|cut -c1-16); b=$(sha256sum "$P/${n}_a.img" 2>/dev/null|cut -c1-16)
  [ "$a" = "$b" ] && echo "  SAME $n" || echo "  DIFF $n ($a != $b)"
done
echo v23_VERIFIED