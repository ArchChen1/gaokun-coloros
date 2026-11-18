#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
echo '===== VENDOR TREE VINTF ====='
find "$B/vendor-tree/etc/vintf" -maxdepth 4 -type f -printf '%P %s\n' 2>/dev/null | sort | head -200
echo '===== GREP network_manifest ====='
grep -R -n 'network_manifest.xml' "$B/vendor-tree" 2>/dev/null | head -100 || true
echo '===== VENDOR ROOT MANIFEST ====='
cat "$B/vendor-tree/etc/vintf/manifest.xml" 2>/dev/null || true
echo '===== VENDOR ROOT COMPAT ====='
cat "$B/vendor-tree/etc/vintf/compatibility_matrix.xml" 2>/dev/null || true