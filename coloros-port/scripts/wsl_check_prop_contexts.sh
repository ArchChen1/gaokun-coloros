#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/cenmin/coloros-trees-xattr
FILES=(
  "$ROOT/system/system/etc/selinux/plat_property_contexts"
  "$ROOT/system_ext/etc/selinux/system_ext_property_contexts"
  "$ROOT/product/etc/selinux/product_property_contexts"
  "$ROOT/vendor/etc/selinux/vendor_property_contexts"
  "$ROOT/odm/etc/selinux/precompiled_property_contexts"
)
for f in "${FILES[@]}"; do
  echo "==== $f"
  if [ -f "$f" ]; then
    file "$f"
    wc -l "$f"
    echo "-- exact hits --"
    grep -a -n -E "remapid|skip_failed_ids|radio_opm" "$f" || true
    echo "-- first 5 --"
    head -5 "$f"
  else
    echo MISSING
  fi
done
echo "==== CIL type hits ===="
for f in "$ROOT"/system/system/etc/selinux/*.cil "$ROOT"/system_ext/etc/selinux/*.cil "$ROOT"/product/etc/selinux/*.cil "$ROOT"/vendor/etc/selinux/*.cil; do
  [ -f "$f" ] || continue
  if grep -a -q -E "vendor_camera_remapid_prop|vendor_camera_skip_failed_ids_prop|vendor_radio_opm_prop" "$f"; then
    echo "FILE $f"
    grep -a -n -E "vendor_camera_remapid_prop|vendor_camera_skip_failed_ids_prop|vendor_radio_opm_prop" "$f" | head -20
  fi
done
