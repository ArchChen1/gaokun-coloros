#!/usr/bin/env bash
set -euo pipefail
P=/home/cenmin/coloros-build/v52
SRC=/home/cenmin/coloros-build/v49/src
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
SUPER=$P/super-coloros-v52.img
ZB=$P/zb
mkdir -p "$ZB"
declare -a N=(system system_ext product vendor odm my_product my_stock my_manifest my_region my_engineering my_heytap my_carrier my_bigball)
declare -a F=(
  "$P/system_a_v52e.erofs"
  "$SRC/system_ext_a.img"
  "$SRC/product_a.img"
  "$P/vendor_a_v52.img"
  "$P/odm_a_v52b.erofs"
  "$P/my_product_a_v52b.erofs"
  "$P/my_stock_a_v52.erofs"
  "$SRC/my_manifest_a.img"
  "$SRC/my_region_a.img"
  "$SRC/my_engineering_a.img"
  "$SRC/my_heytap_a.img"
  "$SRC/my_carrier_a.img"
  "$SRC/my_bigball_a.img"
)
for f in "${F[@]}"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done
total=0; for f in "${F[@]}"; do total=$((total+$(stat -Lc%s "$f"))); done
echo "per-slot: $total  total2: $((total*2))  limit: 21473689088"
cmd=("$OT/lpmake" -S -F -d 21474836480 -m 65536 -s 3 --virtual-ab -b 4096 -g "gaokun3_dynamic_partitions_a:21473689088")
for slot in a b; do
  for i in "${!N[@]}"; do
    if [ "$slot" = a ]; then f=${F[$i]}; else f="$ZB/${N[$i]}_b.img"; [ -f "$f" ] || truncate -s "$(stat -Lc%s "${F[$i]}")" "$f"; fi
    cmd+=(-p "$(printf '%s_%s:none:%d:gaokun3_dynamic_partitions_a' "${N[$i]}" "$slot" "$(stat -Lc%s "$f")")")
  done
done
for i in "${!N[@]}"; do cmd+=(-i "$(printf '%s_a=%s' "${N[$i]}" "${F[$i]}")"); done
for i in "${!N[@]}"; do cmd+=(-i "$(printf '%s_b=%s' "${N[$i]}" "$ZB/${N[$i]}_b.img")"); done
cmd+=(-o "$SUPER")
rm -f "$SUPER"
"${cmd[@]}" > "$P/super-v52.log" 2>&1 || { tail -6 "$P/super-v52.log"; exit 1; }
ls -l "$SUPER"
echo SUPER_V52_DONE
