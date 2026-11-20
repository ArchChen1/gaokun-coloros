#!/bin/bash
set -euo pipefail
I=/home/cenmin/v5/parts/odm_v24_a.img
M=/mnt/v24check
mkdir -p "$M"
cleanup(){ umount "$M" 2>/dev/null || true; }
trap cleanup EXIT
mount -t erofs -o loop,ro "$I" "$M"
P="$M/etc/audio/audio_policy_configuration.xml"
echo "=== removed manifests ==="
for f in manifest_module_binaural_record_V3.xml manifest_module_virtual_audio_v3.xml; do
  if [ -e "$M/etc/vintf/manifest/$f" ]; then echo "STILL $f"; exit 2; else echo "REMOVED $f"; fi
done
echo "=== policy parse ==="
python3 -c "import xml.etree.ElementTree as E; E.parse('$P'); print('XML_PARSE_OK')"
echo "=== policy module refs ==="
grep -nE '<module name=|binaural_record|virtual_audio_policy_configuration|IModule/' "$P"
echo "=== module name count ==="
grep -c '<module name=' "$P"
echo "=== xattr ==="
getfattr --only-values -n security.selinux "$P" 2>/dev/null || true
echo "=== sepolicy unchanged ==="
sha256sum "$M/etc/selinux/precompiled_sepolicy" /home/cenmin/v23-work/precompiled_sepolicy.orig
echo "=== size/hash ==="
stat -c '%s %a %u:%g %n' "$P" "$I"
sha256sum "$I"
echo ODM_V24_CHECK_OK