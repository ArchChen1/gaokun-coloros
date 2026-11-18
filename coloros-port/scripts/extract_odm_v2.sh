#!/bin/bash
set -euo pipefail
ODM=/home/cenmin/odm-final-vintffix.raw.img
T=/tmp/odm-v2
rm -rf "$T"; mkdir -p "$T/root"
fsck.erofs --extract="$T/root" "$ODM" >/tmp/odm-v2-extract.log 2>&1
[ -d "$T/root/etc/init" ] || { cat /tmp/odm-v2-extract.log; exit 1; }
echo 'ODM_V2_EXTRACT_OK'
for f in \
 "$T/root/etc/init/vendor.oplus.hardware.biometrics.face@1.0-service.rc" \
 "$T/root/etc/init/vendor.oplus.hardware.biometrics.fingerprintpay@1.0-service.rc" \
 "$T/root/etc/init/vendor.oplus.hardware.fido.fido2ca@1.0-service.rc" \
 "$T/root/etc/init/vendor.oplus.hardware.fido.fidoca@1.0-service.rc" \
 "$T/root/etc/init/vendor.oplus.hardware.riskdetect-V1-service.rc"; do
  echo "===== $f ====="
  sed -n '1,40p' "$f" 2>/dev/null || echo MISSING
done