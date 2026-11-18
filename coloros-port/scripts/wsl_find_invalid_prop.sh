#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/cenmin/coloros-trees-xattr
FILES=$(find "$ROOT" -name '*property_contexts' -type f 2>/dev/null)
for t in vendor_camera_remapid_prop vendor_camera_skip_failed_ids_prop vendor_radio_opm_prop; do
  echo "==== $t ===="
  for f in $FILES; do
    grep -n -F "$t" "$f" && echo "FILE $f" || true
  done
done
echo "==== all vendor_camera property contexts ===="
for f in $FILES; do grep -n 'vendor_camera_' "$f" && echo "FILE $f" || true; done
