#!/usr/bin/env bash
set -euo pipefail
TREES=/home/cenmin/coloros-trees
OUT=/mnt/e/gaokun-coloros/coloros-port/reports/wsl-real-scan
mkdir -p "$OUT"
for p in system system_ext product vendor odm my_product my_stock my_manifest; do
  echo "==== $p ===="
  python3 /mnt/e/gaokun-coloros/coloros-port/scripts/scan_oppo_deps.py "$TREES/$p" --json "$OUT/$p.json" || true
done
# Collect label examples and missing-label count.
{
  for p in system system_ext product vendor odm my_product my_stock my_manifest; do
    root="$TREES/$p"
    echo "== $p =="
    find "$root" -type f 2>/dev/null | head -n 2000 | while read -r f; do
      label=$(getfattr -n security.selinux --only-values "$f" 2>/dev/null || true)
      printf '%s\t%s\n' "$label" "$f"
    done
  done
} > "$OUT/labels-sample.tsv"
echo "OUTPUT $OUT"
