#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/cenmin/coloros-trees-xattr
# Determine whether the three cited names occur as raw strings anywhere in the
# small SELinux/context files and in the main policy files. This avoids a full
# 16 GiB rescan.
for term in vendor_camera_remapid_prop vendor_camera_skip_failed_ids_prop vendor_radio_opm_prop; do
  echo "==== $term ===="
  find "$ROOT" -path "*/etc/selinux/*" -type f -size -8M -print0 2>/dev/null |
    xargs -0 grep -a -l -F "$term" 2>/dev/null | head -40 || true
done
echo "==== context file tails (non-comment) ===="
for f in "$ROOT"/{system/system,system_ext,product,vendor,odm}/etc/selinux/*property_contexts; do
  [ -f "$f" ] || continue
  echo "---- $f"
  grep -a -v "^#" "$f" | tail -5
done
