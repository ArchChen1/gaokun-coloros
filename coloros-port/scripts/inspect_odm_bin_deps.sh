#!/bin/bash
set -euo pipefail
R=/tmp/odm-current/root
for b in touchDaemon vendor.oplus.hardware.biometrics.face@1.0-service_uff vendor.oplus.hardware.biometrics.fingerprintpay@1.0-service vendor.oplus.hardware.fido.fido2ca@1.0-service vendor.oplus.hardware.fido.fidoca@1.0-service vendor.oplus.hardware.riskdetect-V1-service; do
  p="$R/bin/$b"; [ -f "$p" ] || p="$R/bin/hw/$b"
  echo "===== $b"
  if [ -f "$p" ]; then
    file "$p"
    readelf -l "$p" 2>/dev/null | grep -A1 INTERP || true
    readelf -d "$p" 2>/dev/null | grep NEEDED | head -40 || true
  else echo MISSING; fi
done