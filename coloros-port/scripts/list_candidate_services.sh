#!/bin/bash
set -euo pipefail
V=/tmp/vendor-current/root
R=/tmp/odm-v2/root
echo '===== all fido/fpa/face/risk service names ====='
grep -RhoE '^[[:space:]]*service[[:space:]]+[^[:space:]]+' "$R/etc/init" "$V/etc/init" 2>/dev/null | sed -E 's/^[[:space:]]*service[[:space:]]+//' | sort -u | grep -Ei 'fido|fpa|finger|face|risk|touch|smmu|nurano' || true
echo '===== all files with those service definitions ====='
grep -RIl -Ei '^[[:space:]]*service[[:space:]]+(fido|fpa|finger|face|risk|touch|smmu)' "$R/etc/init" "$V/etc/init" 2>/dev/null | sort
echo '===== init.vendor.soccp file ====='
cat "$R/etc/init/init.vendor.soccp_logger_daemon.rc" 2>/dev/null || true