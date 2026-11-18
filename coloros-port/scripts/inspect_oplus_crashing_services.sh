#!/bin/bash
set -euo pipefail
T=/tmp/super-vintffix-check/root
if [ ! -d "$T" ]; then echo "missing extracted odm: $T"; exit 0; fi
echo '===== matching service rc files ====='
grep -RIn -E 'service (touchDaemon|face_hal|fpa_hal|fido2ca|fido|riskdetect)|touchDaemon|face_hal|fpa_hal|fido2ca|riskdetect' "$T/etc/init" "$T" 2>/dev/null | head -240 || true
echo '===== init.nurano.rc ====='
cat "$T/etc/init/init.nurano.rc" 2>/dev/null || true
echo '===== binaries ====='
for b in vendor.oplus.hardware.riskdetect-V1-service vendor.oplus.hardware.biometrics.face@1.0-service_uff vendor.oplus.hardware.biometrics.fingerprintpay@1.0-service vendor.oplus.hardware.fido.fido2ca@1.0-service vendor.oplus.hardware.fido.fidoca@1.0-service; do
  p="$T/bin/hw/$b"
  if [ -f "$p" ]; then echo "===== $p"; file "$p"; readelf -d "$p" 2>/dev/null | grep NEEDED | head -30; fi
done