#!/usr/bin/env bash
set -euo pipefail
LP=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/lpmake
IMG2SIMG=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/img2simg
D=/mnt/e/gaokun-coloros/coloros-port/work/opd2513
W=/home/cenmin/coloros-build/sparse
OUT=/home/cenmin/coloros-build
mkdir -p "$W" "$OUT"
for p in system system_ext product vendor odm my_product my_stock my_manifest my_engineering my_region my_heytap my_carrier my_bigball; do
  if [ -f "$D/$p.img" ]; then
    echo "sparse $p"
    "$IMG2SIMG" "$D/$p.img" "$W/$p.img"
  fi
done
echo "sizes:"
stat -c '%n %s' "$W"/*.img
