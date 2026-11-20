#!/bin/bash
set -euo pipefail

OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
P=/home/cenmin/v5/parts
SYS=/home/cenmin/v5/system-v25.erofs
V=/home/cenmin/coloros-build/v28/vendor_a_v28.img
ODM=$P/odm_v26_a.img
OUT=/home/cenmin/coloros-build/super-coloros-v28.simg
LOG=/home/cenmin/coloros-build/v28-super-full.log

rm -f "$OUT"
"$OT/lpmake" -S -F -d 12884901888 -m 65536 -s 3 --virtual-ab -b 4096 \
  -g gaokun3_dynamic_partitions_a:12683575296 \
  -p system_a:none:"$(stat -c%s "$SYS")":gaokun3_dynamic_partitions_a \
  -p system_ext_a:none:"$(stat -c%s "$P/system_ext_a.img")":gaokun3_dynamic_partitions_a \
  -p product_a:none:"$(stat -c%s "$P/product_a.img")":gaokun3_dynamic_partitions_a \
  -p vendor_a:none:"$(stat -c%s "$V")":gaokun3_dynamic_partitions_a \
  -p odm_a:none:"$(stat -c%s "$ODM")":gaokun3_dynamic_partitions_a \
  -p my_product_a:none:"$(stat -c%s "$P/my_product_a.img")":gaokun3_dynamic_partitions_a \
  -p my_stock_a:none:"$(stat -c%s "$P/my_stock_a.img")":gaokun3_dynamic_partitions_a \
  -p my_manifest_a:none:"$(stat -c%s "$P/my_manifest_a.img")":gaokun3_dynamic_partitions_a \
  -p my_region_a:none:"$(stat -c%s "$P/my_region_a.img")":gaokun3_dynamic_partitions_a \
  -p my_engineering_a:none:"$(stat -c%s "$P/my_engineering_a.img")":gaokun3_dynamic_partitions_a \
  -p my_heytap_a:none:"$(stat -c%s "$P/my_heytap_a.img")":gaokun3_dynamic_partitions_a \
  -p my_carrier_a:none:"$(stat -c%s "$P/my_carrier_a.img")":gaokun3_dynamic_partitions_a \
  -p my_bigball_a:none:"$(stat -c%s "$P/my_bigball_a.img")":gaokun3_dynamic_partitions_a \
  -i system_a="$SYS" -i system_ext_a="$P/system_ext_a.img" -i product_a="$P/product_a.img" \
  -i vendor_a="$V" -i odm_a="$ODM" \
  -i my_product_a="$P/my_product_a.img" -i my_stock_a="$P/my_stock_a.img" \
  -i my_manifest_a="$P/my_manifest_a.img" -i my_region_a="$P/my_region_a.img" \
  -i my_engineering_a="$P/my_engineering_a.img" -i my_heytap_a="$P/my_heytap_a.img" \
  -i my_carrier_a="$P/my_carrier_a.img" -i my_bigball_a="$P/my_bigball_a.img" \
  -o "$OUT" >"$LOG" 2>&1
ls -lh "$OUT"
sha256sum "$OUT"
tail -20 "$LOG"
echo SUPER_V28_BUILT
