#!/bin/bash
set -euo pipefail
R=/tmp/odm-v2/root
echo '===== ODM late_start services ====='
find "$R/etc/init" -type f -name '*.rc' -print0 | xargs -0 awk '
  function flush(){ if (svc!="") print FILENAME ": " svc " | class=" cls " | disabled=" dis " | iface=" iface; svc=""; cls=""; dis="no"; iface=""; }
  /^[[:space:]]*service[[:space:]]+/ { flush(); svc=$0; sub(/^[[:space:]]*service[[:space:]]+/,"",svc); next }
  /^[[:space:]]*on[[:space:]]+/ { flush(); next }
  svc!="" && /^[[:space:]]*class[[:space:]]+/ { cls=$0; sub(/^[[:space:]]*class[[:space:]]+/,"",cls) }
  svc!="" && /^[[:space:]]*disabled([[:space:]]|$)/ { dis="yes" }
  svc!="" && /^[[:space:]]*interface[[:space:]]+/ { iface=$0; sub(/^[[:space:]]*interface[[:space:]]+/,"",iface) }
  END { flush() }
' | grep 'class=.*late_start' | sort