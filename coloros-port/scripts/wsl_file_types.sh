#!/usr/bin/env bash
set -euo pipefail
D=/mnt/e/gaokun-coloros/coloros-port/work/opd2513
for p in system system_ext product vendor odm my_product my_stock my_manifest; do
  echo -n "$p "
  stat -c %s "$D/$p.img"
  file -b "$D/$p.img"
done
