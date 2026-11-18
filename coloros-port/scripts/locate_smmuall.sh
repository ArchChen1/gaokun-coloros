#!/bin/bash
set -euo pipefail
echo '===== locate smmu-notali across all extracted trees ====='
find /tmp /home/cenmin -type f \( -name 'smmu-notali.sh' -o -name '*smmu*notali*' \) -printf '%p %s\n' 2>/dev/null | head -50
echo '===== locate gaokun3_smmuall policy ====='
grep -RIl 'gaokun3_smmuall' /tmp/odm-current /tmp/vendor-current /home/cenmin/coloros-build 2>/dev/null | head -30 || true
echo '===== odm init files ====='
find /tmp/odm-current/root/etc/init -maxdepth 2 -type f -printf '%P\n' 2>/dev/null | sort | head -200