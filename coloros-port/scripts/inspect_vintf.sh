#!/bin/bash
set -euo pipefail
R=/tmp/system-extract
echo '===== SYSTEM VINTF ====='
find "$R/system/etc/vintf" -maxdepth 4 -type f -printf '%p %s\n' | sort | head -200
echo '===== KEYMINT SERVICE VINTF ====='
grep -R -n -E 'keymint|keymaster|security.maintenance|boot.IBootControl' "$R/system/etc/vintf" "$R/system_ext/etc/vintf" "$R/product/etc/vintf" 2>/dev/null | head -200 || true