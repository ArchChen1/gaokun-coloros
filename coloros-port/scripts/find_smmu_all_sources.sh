#!/bin/bash
set -euo pipefail
echo '===== build tree refs ====='
grep -RIl -E 'smmu-notali|gaokun3_smmuall|nomodcms1' /home/cenmin/coloros-build /tmp/odm-current /tmp/vendor-current 2>/dev/null | head -100 || true
echo '===== workspace refs ====='
grep -RIl -E 'smmu-notali|gaokun3_smmuall|nomodcms1' /mnt/e/gaokun-coloros/analysis /mnt/e/gaokun-coloros/coloros-port 2>/dev/null | head -100 || true
echo '===== vendor file listing smmu ====='
find /tmp/vendor-current/root -iname '*smmu*' -printf '%M %s %p\n' 2>/dev/null | head -100