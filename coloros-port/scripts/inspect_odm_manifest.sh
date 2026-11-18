#!/bin/bash
set -euo pipefail
T=${TMPDIR:-/tmp}/odm-inspect
D=$T/final-merged/etc/vintf
echo '===== ROOT FILES ====='
find "$D" -maxdepth 1 -type f -printf '%f %s\n' | sort
echo '===== manifest.xml ====='
cat "$D/manifest.xml" 2>/dev/null || true
echo '===== compatibility_matrix.xml ====='
cat "$D/compatibility_matrix.xml" 2>/dev/null || true
echo '===== grep network_manifest references ====='
grep -R -n 'network_manifest.xml\|manifest/network' "$D" 2>/dev/null || true
echo '===== all network-related files ====='
find "$D" -type f -iname '*network*' -printf '%p %s\n' | sort || true