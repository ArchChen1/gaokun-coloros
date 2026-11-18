#!/bin/bash
set -euo pipefail
R=/tmp/odm-v2/root
declare -A FILES=(
 [face_hal]="$R/etc/init/vendor.oplus.hardware.biometrics.face@1.0-service.rc"
 [fpay_hal]="$R/etc/init/vendor.oplus.hardware.biometrics.fingerprintpay@1.0-service.rc"
 [fido2ca]="$R/etc/init/vendor.oplus.hardware.fido.fido2ca@1.0-service.rc"
 [fidoca]="$R/etc/init/vendor.oplus.hardware.fido.fidoca@1.0-service.rc"
 [riskdetect]="$R/etc/init/vendor.oplus.hardware.riskdetect-V1-service.rc"
)
for svc in "${!FILES[@]}"; do
  f=${FILES[$svc]}
  [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }
  if ! grep -qE "^[[:space:]]*disabled([[:space:]]|$)" "$f"; then
    awk -v svc="$svc" '
      $1=="service" && $2==svc {inblock=1; print; next}
      inblock && /^[[:space:]]*$/ {print "    disabled"; inblock=0; print; next}
      inblock && /^on[[:space:]]/ {print "    disabled"; inblock=0; print; next}
      {print}
      END {if (inblock) print "    disabled"}
    ' "$f" > "$f.new"
    mv "$f.new" "$f"
    echo "disabled $svc in $f"
  else
    echo "already disabled $svc"
  fi
done
echo '===== verify ====='
for f in "${FILES[@]}"; do echo "--- $f"; sed -n '1,28p' "$f"; done