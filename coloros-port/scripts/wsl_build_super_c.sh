#!/bin/bash
set -euo pipefail
LPTools=${LPTools:-/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin}
ROOT=${ROOT:-/home/cenmin/coloros-build}
PARTS=${PARTS:-/mnt/e/gaokun-coloros/coloros-port/work/opd2513}
SPARSE=${SPARSE:-$ROOT/sparse}
VENDOR=${VENDOR:-$ROOT/vendor-gaokun-patched.img}
ODM=${ODM:-/home/cenmin/odm-final.raw.img}
OUTPUT=${OUTPUT:-$ROOT/super-coloros-c-merged.img}
ODM_SPARSE="$SPARSE/odm-final-merged.img"
[ -f "$VENDOR" ] || { echo "missing vendor: $VENDOR" >&2; exit 1; }
[ -f "$ODM" ] || { echo "missing odm: $ODM" >&2; exit 1; }
[ -x "$LPTools/lpmake" ] || { echo "missing lpmake" >&2; exit 1; }
[ -x "$LPTools/img2simg" ] || { echo "missing img2simg" >&2; exit 1; }
"$LPTools/img2simg" "$ODM" "$ODM_SPARSE"
odm_size=$(stat -c%s "$ODM")
"$LPTools/lpmake" -F -d 12884901888 -m 65536 -s 3 --virtual-ab -b 4096 \
  -g gaokun3_dynamic_partitions_a:12683575296 \
  -p system_a:none:$(stat -c%s "$PARTS/system.img"):gaokun3_dynamic_partitions_a \
  -p system_ext_a:none:$(stat -c%s "$PARTS/system_ext.img"):gaokun3_dynamic_partitions_a \
  -p product_a:none:$(stat -c%s "$PARTS/product.img"):gaokun3_dynamic_partitions_a \
  -p vendor_a:none:$(stat -c%s "$VENDOR"):gaokun3_dynamic_partitions_a \
  -p odm_a:none:$odm_size:gaokun3_dynamic_partitions_a \
  -p my_product_a:none:$(stat -c%s "$PARTS/my_product.img"):gaokun3_dynamic_partitions_a \
  -p my_stock_a:none:$(stat -c%s "$PARTS/my_stock.img"):gaokun3_dynamic_partitions_a \
  -p my_manifest_a:none:$(stat -c%s "$PARTS/my_manifest.img"):gaokun3_dynamic_partitions_a \
  -p my_region_a:none:$(stat -c%s "$PARTS/my_region.img"):gaokun3_dynamic_partitions_a \
  -p my_engineering_a:none:$(stat -c%s "$PARTS/my_engineering.img"):gaokun3_dynamic_partitions_a \
  -p my_heytap_a:none:$(stat -c%s "$PARTS/my_heytap.img"):gaokun3_dynamic_partitions_a \
  -p my_carrier_a:none:$(stat -c%s "$PARTS/my_carrier.img"):gaokun3_dynamic_partitions_a \
  -p my_bigball_a:none:$(stat -c%s "$PARTS/my_bigball.img"):gaokun3_dynamic_partitions_a \
  -i system_a="$SPARSE/system.img" \
  -i system_ext_a="$SPARSE/system_ext.img" \
  -i product_a="$SPARSE/product.img" \
  -i vendor_a="$ROOT/sparse/vendor-gaokun-patched.img" \
  -i odm_a="$ODM_SPARSE" \
  -i my_product_a="$SPARSE/my_product.img" \
  -i my_stock_a="$SPARSE/my_stock.img" \
  -i my_manifest_a="$SPARSE/my_manifest.img" \
  -i my_region_a="$SPARSE/my_region.img" \
  -i my_engineering_a="$SPARSE/my_engineering.img" \
  -i my_heytap_a="$SPARSE/my_heytap.img" \
  -i my_carrier_a="$SPARSE/my_carrier.img" \
  -i my_bigball_a="$SPARSE/my_bigball.img" \
  -o "$OUTPUT"
sha256sum "$OUTPUT"
