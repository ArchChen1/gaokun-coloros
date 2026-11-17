#!/usr/bin/env bash
set -euo pipefail
LP=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/lpmake
IMG2SIMG=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/img2simg
S=/home/cenmin/coloros-build/sparse
B=/home/cenmin/coloros-build
D=/mnt/e/gaokun-coloros/coloros-port/work/opd2513
V=$B/vendor-gaokun-patched.img
VS=$S/vendor-gaokun-patched.img
OUT=$B/super-coloros-a.img
if [ ! -f "$VS" ]; then
  "$IMG2SIMG" "$V" "$VS"
fi
system=$(stat -c%s "$D/system.img")
system_ext=$(stat -c%s "$D/system_ext.img")
product=$(stat -c%s "$D/product.img")
odm=$(stat -c%s "$D/odm.img")
my_product=$(stat -c%s "$D/my_product.img")
my_stock=$(stat -c%s "$D/my_stock.img")
my_manifest=$(stat -c%s "$D/my_manifest.img")
my_region=$(stat -c%s "$D/my_region.img")
my_engineering=$(stat -c%s "$D/my_engineering.img")
my_heytap=$(stat -c%s "$D/my_heytap.img")
my_carrier=$(stat -c%s "$D/my_carrier.img")
my_bigball=$(stat -c%s "$D/my_bigball.img")
vendor=$(stat -c%s "$V")
echo "sizes: system=$system system_ext=$system_ext product=$product vendor=$vendor"
echo "sizes: odm=$odm my_product=$my_product my_stock=$my_stock"
"$LP" -F -d 12884901888 -m 65536 -s 3 --virtual-ab -b 4096 \
  -g gaokun3_dynamic_partitions_a:12683575296 \
  -p system_a:none:$system:gaokun3_dynamic_partitions_a \
  -p system_ext_a:none:$system_ext:gaokun3_dynamic_partitions_a \
  -p product_a:none:$product:gaokun3_dynamic_partitions_a \
  -p vendor_a:none:$vendor:gaokun3_dynamic_partitions_a \
  -p odm_a:none:$odm:gaokun3_dynamic_partitions_a \
  -p my_product_a:none:$my_product:gaokun3_dynamic_partitions_a \
  -p my_stock_a:none:$my_stock:gaokun3_dynamic_partitions_a \
  -p my_manifest_a:none:$my_manifest:gaokun3_dynamic_partitions_a \
  -p my_region_a:none:$my_region:gaokun3_dynamic_partitions_a \
  -p my_engineering_a:none:$my_engineering:gaokun3_dynamic_partitions_a \
  -p my_heytap_a:none:$my_heytap:gaokun3_dynamic_partitions_a \
  -p my_carrier_a:none:$my_carrier:gaokun3_dynamic_partitions_a \
  -p my_bigball_a:none:$my_bigball:gaokun3_dynamic_partitions_a \
  -i system_a="$S/system.img" \
  -i system_ext_a="$S/system_ext.img" \
  -i product_a="$S/product.img" \
  -i vendor_a="$VS" \
  -i odm_a="$S/odm.img" \
  -i my_product_a="$S/my_product.img" \
  -i my_stock_a="$S/my_stock.img" \
  -i my_manifest_a="$S/my_manifest.img" \
  -i my_region_a="$S/my_region.img" \
  -i my_engineering_a="$S/my_engineering.img" \
  -i my_heytap_a="$S/my_heytap.img" \
  -i my_carrier_a="$S/my_carrier.img" \
  -i my_bigball_a="$S/my_bigball.img" \
  -o "$OUT"
ls -lh "$OUT"
sha256sum "$OUT"
