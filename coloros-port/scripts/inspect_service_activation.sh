#!/bin/bash
set -euo pipefail
R=/tmp/odm-current/root
for svc in touchDaemon face_hal fidoca fido2ca riskdetect fpay_hal; do
  echo "===== $svc ====="
  grep -RIn -E "^service[[:space:]]+$svc([[:space:]]|$)" "$R/etc/init" 2>/dev/null | head -10 || true
  grep -RIn -E "(enabled|disabled|oneshot|interface|class|user|group|socket|on boot|on late-fs|on post-fs-data)" "$R/etc/init" 2>/dev/null | grep -A0 -B0 "$svc" | head -20 || true
done
echo '===== on boot starts ====='
grep -RIn -E 'start (touchDaemon|face_hal|fidoca|fido2ca|riskdetect|fpay_hal)' "$R/etc/init" 2>/dev/null | head -100 || true