#!/bin/bash
set -euo pipefail
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
S=/home/cenmin/coloros-build/super-coloros-v24.simg
V=/home/cenmin/v24verify
P=/home/cenmin/v5/parts
rm -rf "$V"; mkdir -p "$V"
"$OT/simg2img" "$S" "$V/raw.img"
"$OT/lpunpack" "$V/raw.img" "$V" >/dev/null 2>&1
rm -f "$V/raw.img"
echo "=== ODM exact ==="
sha256sum "$V/odm_a.img" "$P/odm_v24_a.img"
echo "=== ODM policy/manifests ==="
M=/mnt/v24verify-mount
mkdir -p "$M"
mount -t erofs -o loop,ro "$V/odm_a.img" "$M"
python3 -c "import xml.etree.ElementTree as E; E.parse('$M/etc/audio/audio_policy_configuration.xml'); print('XML_PARSE_OK')"
grep -nE 'binaural_record|virtual_audio_policy|IModule/' "$M/etc/audio/audio_policy_configuration.xml" || true
for f in manifest_module_binaural_record_V3.xml manifest_module_virtual_audio_v3.xml; do
  test ! -e "$M/etc/vintf/manifest/$f" && echo "REMOVED $f"
done
umount "$M"
echo "=== other partitions ==="
for n in system system_ext product vendor my_product my_stock my_manifest my_region my_engineering my_heytap my_carrier my_bigball; do
  a=$(sha256sum "$V/${n}_a.img" 2>/dev/null | cut -c1-16)
  b=$(sha256sum "$P/${n}_a.img" 2>/dev/null | cut -c1-16)
  if [ "$a" = "$b" ]; then echo "SAME $n"; else echo "DIFF $n $a $b"; fi
done
echo V24_VERIFIED