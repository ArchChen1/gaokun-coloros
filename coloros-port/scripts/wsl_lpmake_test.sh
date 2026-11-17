#!/usr/bin/env bash
set -euo pipefail
LP=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/lpmake
D=/mnt/e/gaokun-coloros/coloros-port/work/opd2513
OUT=/home/cenmin/coloros-build
mkdir -p "$OUT"
"$LP" \
  -d 12884901888 \
  -m 65536 \
  -s 3 \
  --virtual-ab \
  -b 4096 \
  -g gaokun3_dynamic_partitions_a:12683575296 \
  -p system:none:$(stat -c%s "$D/system.img"):gaokun3_dynamic_partitions_a \
  -p system_ext:none:$(stat -c%s "$D/system_ext.img"):gaokun3_dynamic_partitions_a \
  -p product:none:$(stat -c%s "$D/product.img"):gaokun3_dynamic_partitions_a \
  -p vendor:none:$(stat -c%s "$D/vendor.img"):gaokun3_dynamic_partitions_a \
  -i system="$D/system.img" \
  -i system_ext="$D/system_ext.img" \
  -i product="$D/product.img" \
  -i vendor="$D/vendor.img" \
  -o "$OUT/super-test.img"
ls -l "$OUT/super-test.img"
