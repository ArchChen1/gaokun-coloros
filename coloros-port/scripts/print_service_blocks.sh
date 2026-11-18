#!/bin/bash
set -euo pipefail
for d in /tmp/odm-current/root /tmp/vendor-current/root; do
  echo "===== $d ====="
  for svc in touchDaemon face_hal fidoca fido2ca riskdetect fpay_hal; do
    f=$(grep -RIl -E "^service[[:space:]]+$svc([[:space:]]|$)" "$d/etc/init" 2>/dev/null | head -1)
    [ -z "$f" ] && continue
    echo "--- $svc ($f) ---"
    awk -v s="service $svc" 'index($0,s)==1 || $0 ~ "^service[[:space:]]+"s"([[:space:]]|$)" {p=1} p{print} p && /^[[:space:]]*$/{exit}' "$f"
  done
done