#!/bin/bash
set -euo pipefail
M=/mnt/v23check
mkdir -p "$M"
mount -t erofs -o loop,ro /home/cenmin/v23verify/odm_a.img "$M"
cleanup() { umount "$M" 2>/dev/null || true; }
trap cleanup EXIT
P="$M/etc/audio/audio_policy_configuration.xml"
test -s "$P"
python3 -c "import xml.etree.ElementTree as E; E.parse('$P'); print('XML_PARSE_OK')"
if grep -q 'name="binaural_record"' "$P"; then
  echo BINAURAL_STILL_PRESENT
  exit 2
fi
echo BINAURAL_REMOVED
grep -o 'module name="[^"]*"' "$P" | head -30
stat -c 'policy %s bytes, %a %u:%g' "$P"
test -s "$M/etc/selinux/precompiled_sepolicy"
sha256sum "$M/etc/selinux/precompiled_sepolicy"
getfattr --only-values -n security.selinux "$P" 2>/dev/null || true
echo ODM_FINAL_CHECK_OK
