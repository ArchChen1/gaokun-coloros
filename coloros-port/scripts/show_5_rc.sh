#!/bin/bash
set -euo pipefail
R=/tmp/odm-current/root
for f in \
 "$R/etc/init/vendor.oplus.hardware.biometrics.face@1.0-service.rc" \
 "$R/etc/init/vendor.oplus.hardware.biometrics.fingerprintpay@1.0-service.rc" \
 "$R/etc/init/vendor.oplus.hardware.fido.fido2ca@1.0-service.rc" \
 "$R/etc/init/vendor.oplus.hardware.fido.fidoca@1.0-service.rc" \
 "$R/etc/init/vendor.oplus.hardware.riskdetect-V1-service.rc"; do
  echo "===== $f ====="
  cat "$f"
done