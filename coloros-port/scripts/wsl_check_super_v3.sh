#!/bin/bash
set -euo pipefail
L=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
T=/tmp/super-v3-check
rm -rf "$T"
mkdir -p "$T"
"$L/simg2img" /home/cenmin/coloros-build/super-coloros-v3.simg "$T/super.raw"
"$L/lpunpack" -p odm_a "$T/super.raw" "$T"
ODM="$T/odm_a.img"
[ -f "$ODM" ] || { echo "odm extraction failed" >&2; exit 1; }
mkdir -p "$T/root"
fsck.erofs --extract="$T/root" "$ODM" >/tmp/odm-v3-readback.log 2>&1
FILES=(
 'etc/init/init.touchDaemon.rc'
 'etc/init/vendor.oplus.hardware.biometrics.face@1.0-service.rc'
 'etc/init/vendor.oplus.hardware.biometrics.fingerprintpay@1.0-service.rc'
 'etc/init/vendor.oplus.hardware.fido.fido2ca@1.0-service.rc'
 'etc/init/vendor.oplus.hardware.fido.fidoca@1.0-service.rc'
 'etc/init/vendor.oplus.hardware.riskdetect-V1-service.rc'
)
for rel in "${FILES[@]}"; do
  grep -q '^[[:space:]]*disabled' "$T/root/$rel" || { echo "NOT DISABLED $rel" >&2; exit 1; }
  echo "DISABLED_OK $rel"
done
test ! -e "$T/root/etc/vintf/manifest/network_manifest.xml"
actual=$(sha256sum "$T/root/etc/selinux/precompiled_sepolicy" | awk '{print $1}')
expected=3fb220b5ee9f0edb132b760c2c2ca54b597a1a05a2d3f03ca28885d12ef70288
test "$actual" = "$expected"
echo SUPER_V3_READBACK_OK
echo "policy=$actual"