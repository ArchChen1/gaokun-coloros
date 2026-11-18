#!/bin/bash
set -euo pipefail
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
RAW=/home/cenmin/v5verify/super-v5.raw.img
P=/home/cenmin/v5/parts
mkdir -p "$P"
echo "=== unpack all logical partitions from existing v5 raw ==="
time "$OT/lpunpack" "$RAW" "$P" 2>&1 | tail -20
echo
echo "=== result ==="
ls -lh "$P"/*.img