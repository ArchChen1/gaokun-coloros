#!/usr/bin/env bash
set -euo pipefail
LP=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/lpmake
OUT=/home/cenmin/coloros-build/name-test-full.img
rm -f "$OUT"
"$LP" -F -d 104857600 -m 65536 -s 3 --virtual-ab -b 4096 \
  -g gaokun3_dynamic_partitions_a:104857600 \
  -p system:none:1048576:gaokun3_dynamic_partitions_a \
  -p my_stock:none:1048576:gaokun3_dynamic_partitions_a \
  -o "$OUT"
ls -l "$OUT"
cp "$OUT" /mnt/e/gaokun-coloros/coloros-port/work/name-test-full.img
chmod 644 /mnt/e/gaokun-coloros/coloros-port/work/name-test-full.img
