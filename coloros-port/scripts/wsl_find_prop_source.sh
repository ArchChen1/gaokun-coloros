#!/usr/bin/env bash
set -euo pipefail
ROOT=/home/cenmin/coloros-trees-xattr
for term in vendor_camera_remapid_prop vendor_camera_skip_failed_ids_prop vendor_radio_opm_prop; do
  echo "==== $term ===="
  find "$ROOT" -path "*/etc/*" -type f -size -4M -print0 2>/dev/null |
    xargs -0 grep -a -l -F "$term" 2>/dev/null | head -40 || true
done
echo "==== all property context files under etc ===="
find "$ROOT" -path "*/etc/*" -type f -name "*property_contexts" -printf "%p %s\n" 2>/dev/null | sort
