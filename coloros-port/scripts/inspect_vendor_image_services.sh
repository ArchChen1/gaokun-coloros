#!/bin/bash
set -euo pipefail
V=/home/cenmin/coloros-build/vendor-gaokun-patched.img
T=/tmp/vendor-current
rm -rf "$T"; mkdir -p "$T/root"
debugfs -R 'rdump / '"$T/root" "$V" >/tmp/vendor-rdump.log 2>&1 || { cat /tmp/vendor-rdump.log; exit 1; }
echo 'VENDOR_RDUMP_OK'
echo '===== smmu references ====='
grep -RIn -E 'smmu-notali|smmuall|smmustall|nomodcms1|logdchecker_switch' "$T/root" 2>/dev/null | head -240 || true
echo '===== vendor service rc ====='
find "$T/root/etc/init" -type f -name '*.rc' -printf '%p\n' 2>/dev/null | sort | head -200