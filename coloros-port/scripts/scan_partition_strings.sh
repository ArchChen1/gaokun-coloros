#!/bin/bash
set -euo pipefail
ROOT=/mnt/e/gaokun-coloros/coloros-port/work/opd2513
SP=/home/cenmin/coloros-build/sparse
echo '===== search work/opd2513 images ====='
for img in "$ROOT"/*.img; do
  [ -f "$img" ] || continue
  hits=$(grep -aIl -E 'smmu-notali|init\.nurano|nomodcms1|touchDaemon|gaokun3_smmuall' "$img" 2>/dev/null || true)
  if [ -n "$hits" ]; then echo "--- $img"; echo "$hits" | sed "s|$img||g"; fi
done
echo '===== search sparse images ====='
for img in "$SP"/*.img; do
  [ -f "$img" ] || continue
  hits=$(grep -aIl -E 'smmu-notali|init\.nurano|nomodcms1|touchDaemon|gaokun3_smmuall' "$img" 2>/dev/null || true)
  if [ -n "$hits" ]; then echo "--- $img"; fi
done