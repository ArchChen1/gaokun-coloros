#!/bin/bash
set -euo pipefail
ODM=/home/cenmin/odm-final-vintffix.raw.img
T=/tmp/odm-current
rm -rf "$T"; mkdir -p "$T/root"
fsck.erofs --extract="$T/root" "$ODM" >/tmp/odm-current-extract.log 2>&1
[ -d "$T/root/etc/init" ] || { cat /tmp/odm-current-extract.log; echo 'ODM_EXTRACT_FAILED'; exit 1; }
echo 'ODM_EXTRACT_OK'
echo '===== services in ODM ====='
grep -RhoE '^[[:space:]]*service[[:space:]]+[A-Za-z0-9_.@-]+' "$T/root/etc/init" 2>/dev/null | sed -E 's/^[[:space:]]*service[[:space:]]+//' | sort -u
echo '===== matching rc ====='
grep -RIn -E 'fpa_hal|touchDaemon|face_hal|fido2ca|fidoca|riskdetect|nomodcms1|smmu-notali|logdchecker_switch' "$T/root/etc/init" 2>/dev/null | head -240 || true