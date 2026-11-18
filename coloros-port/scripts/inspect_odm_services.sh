#!/bin/bash
set -euo pipefail
ODM=/home/cenmin/odm-final-vintffix.raw.img
T=/tmp/odm-current
rm -rf "$T"; mkdir -p "$T/root"
fsck.erofs --extract="$T/root" "$ODM" >/tmp/odm-current-extract.log 2>&1
echo '===== service definitions ====='
grep -RIn -E 'service[[:space:]]+(touchDaemon|face_hal|fpa_hal|fido2ca|fido|riskdetect)' "$T/root" 2>/dev/null | head -100 || true
echo '===== surrounding rc files ====='
for f in $(grep -RIl -E 'service[[:space:]]+(touchDaemon|face_hal|fpa_hal|fido2ca|fido|riskdetect)' "$T/root" 2>/dev/null); do
  echo "===== $f"
  grep -n -B3 -A16 -E 'service[[:space:]]+(touchDaemon|face_hal|fpa_hal|fido2ca|fido|riskdetect)' "$f"
done
echo '===== smmu-notali ====='
find "$T/root" -iname '*smmu*' -printf '%M %u:%g %s %p\n' | sort
echo '===== nomodcms / nurano ====='
grep -RIn -E 'nomodcms1|smmu-notali|smmu' "$T/root/etc/init" "$T/root/bin" 2>/dev/null | head -160 || true