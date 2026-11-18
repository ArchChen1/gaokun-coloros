#!/bin/bash
set -euo pipefail
# Narrow search: only the candidate trees and with maxdepth.
for d in /tmp/odm-current/root /tmp/vendor-current/root /tmp/super-vintffix-check/root; do
  [ -d "$d" ] || continue
  echo "===== $d ====="
  find "$d" -maxdepth 6 -type f -iname '*smmu*' -printf '%p %s\n' 2>/dev/null | head -80
  grep -RIl 'smmu-notali\|gaokun3_smmuall' "$d/etc" "$d/bin" 2>/dev/null | head -40 || true
done