#!/bin/bash
set -euo pipefail
R=/tmp/odm-current/root
echo '===== fpa_hal ====='
grep -RIn -E 'service[[:space:]]+fpa_hal|fpa_hal' "$R/etc/init" 2>/dev/null | head -100 || true
echo '===== all rc lines with class late_start/core/main and interface ====='
grep -RIn -E '^[[:space:]]*(service|class|interface|disabled)' "$R/etc/init" 2>/dev/null | head -300 || true
echo '===== init.nurano location ====='
find "$R" -name 'init.nurano.rc' -printf '%p %s\n' 2>/dev/null
echo '===== nomodcms refs ====='
grep -RIn 'nomodcms1' "$R" 2>/dev/null | head -80 || true
echo '===== smmu scripts ====='
find "$R" -type f -name 'smmu-notali.sh' -printf '%p %s\n' 2>/dev/null