#!/bin/bash
set -euo pipefail
ROOT=/tmp/odm-current/root
echo '===== init.nurano.rc ====='
cat "$ROOT/etc/init/init.nurano.rc" 2>/dev/null || true
echo '===== all service definitions in ODM ====='
for f in $(find "$ROOT/etc/init" -type f -name '*.rc' | sort); do
  awk -v F="$f" '
    /^[[:space:]]*service[[:space:]]+/ {
      if (svc!="") print F ": " svc " | " body;
      svc=$0; body="";
      next
    }
    /^[[:space:]]*on[[:space:]]+/ {
      if (svc!="") { print F ": " svc " | " body; svc=""; body="" }
      next
    }
    svc!="" { body=body " " $0 }
    END { if (svc!="") print F ": " svc " | " body }
  ' "$f"
done | sed 's/[[:space:]]\+/ /g' | head -400