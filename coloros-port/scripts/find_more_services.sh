#!/bin/bash
set -euo pipefail
for d in /home/cenmin/coloros-build/vendor-tree /tmp/odm-current/root; do
  echo "===== $d ====="
  grep -RIn -E 'service[[:space:]]+(fpa_hal|logdchecker_switch|smmu-notali)|smmu-notali|nomodcms1|oplusreserve' "$d/etc/init" "$d" 2>/dev/null | head -240 || true
done