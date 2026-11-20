#!/bin/bash
set -u
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
P=/home/cenmin/v5/parts
SYS=/home/cenmin/v5/system-v5b.erofs
V=$P/vendor_a_v21.img
OUT=/home/cenmin/coloros-build/super-coloros-v23.simg
LOG=/home/cenmin/coloros-build/v23-super-full.log

echo "=== prerequisites ==="
command -v "$OT/lpmake" || exit 10
stat -c 'system %s bytes %n' "$SYS" || exit 11
stat -c 'vendor %s bytes %n' "$V" || exit 12
mkdir -p /home/cenmin/coloros-build || exit 13

echo "=== space before ==="
df -h /home/cenmin/coloros-build

echo "=== remove old output ==="
rm -f "$OUT"

echo "=== lpmake start $(date -Is) ==="
"$OT/lpmake" -S -F -d 12884901888 -m 65536 -s 3 --virtual-ab -b 4096 \
  -g gaokun3_dynamic_partitions_a:12683575296 \
  -p system_a:none:"$(stat -c%s "$SYS")":gaokun3_dynamic_partitions_a \
  -p system_ext_a:none:"$(stat -c%s "$P/system_ext_a.img")":gaokun3_dynamic_partitions_a \
  -p product_a:none:"$(stat -c%s "$P/product_a.img")":gaokun3_dynamic_partitions_a \
  -p vendor_a:none:"$(stat -c%s "$V")":gaokun3_dynamic_partitions_a \
  -p odm_a:none:"$(stat -c%s "$P/odm_v23_a.img")":gaokun3_dynamic_partitions_a \
  -p my_product_a:none:"$(stat -c%s "$P/my_product_a.img")":gaokun3_dynamic_partitions_a \
  -p my_stock_a:none:"$(stat -c%s "$P/my_stock_a.img")":gaokun3_dynamic_partitions_a \
  -p my_manifest_a:none:"$(stat -c%s "$P/my_manifest_a.img")":gaokun3_dynamic_partitions_a \
  -p my_region_a:none:"$(stat -c%s "$P/my_region_a.img")":gaokun3_dynamic_partitions_a \
  -p my_engineering_a:none:"$(stat -c%s "$P/my_engineering_a.img")":gaokun3_dynamic_partitions_a \
  -p my_heytap_a:none:"$(stat -c%s "$P/my_heytap_a.img")":gaokun3_dynamic_partitions_a \
  -p my_carrier_a:none:"$(stat -c%s "$P/my_carrier_a.img")":gaokun3_dynamic_partitions_a \
  -p my_bigball_a:none:"$(stat -c%s "$P/my_bigball_a.img")":gaokun3_dynamic_partitions_a \
  -i system_a="$SYS" -i system_ext_a="$P/system_ext_a.img" -i product_a="$P/product_a.img" \
  -i vendor_a="$V" -i odm_a="$P/odm_v23_a.img" \
  -i my_product_a="$P/my_product_a.img" -i my_stock_a="$P/my_stock_a.img" \
  -i my_manifest_a="$P/my_manifest_a.img" -i my_region_a="$P/my_region_a.img" \
  -i my_engineering_a="$P/my_engineering_a.img" -i my_heytap_a="$P/my_heytap_a.img" \
  -i my_carrier_a="$P/my_carrier_a.img" -i my_bigball_a="$P/my_bigball_a.img" \
  -o "$OUT" >"$LOG" 2>&1
RC=$?
echo "lpmake rc=$RC"
echo "=== full log ==="
cat "$LOG"
echo "=== result ==="
if [ "$RC" -ne 0 ]; then
  echo LPMAKE_FAILED
  exit "$RC"
fi
ls -lh "$OUT"
sha256sum "$OUT"
echo SUPER_v23_BUILT
