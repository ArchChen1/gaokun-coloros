#!/bin/bash
set -euo pipefail
L=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
T=/tmp/super-vintffix-check
rm -rf "$T"; mkdir -p "$T"
"$L/simg2img" /home/cenmin/coloros-build/super-coloros-vintffix.simg "$T/super.raw"
"$L/lpunpack" -p odm_a "$T/super.raw" "$T"
ODM="$T/odm_a.img"
[ -f "$ODM" ] || { echo 'no odm extracted' >&2; ls -la "$T"; exit 1; }
ls -lh "$ODM"
mkdir -p "$T/root"
fsck.erofs --extract="$T/root" "$ODM" >/tmp/odm-check.log 2>&1
BAD="$T/root/etc/vintf/manifest/network_manifest.xml"
if [ -e "$BAD" ]; then echo 'ERROR bad link present' >&2; exit 1; fi
echo "vintf_regular_files=$(find "$T/root/etc/vintf" -type f | wc -l)"
echo "vintf_symlinks=$(find "$T/root/etc/vintf" -type l | wc -l)"
sha256sum "$T/root/etc/selinux/precompiled_sepolicy"
echo 'ODM_READBACK_OK'