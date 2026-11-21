#!/bin/bash
set -euo pipefail

OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
CB=/home/cenmin/coloros-build
B="$CB/v43"
P=/home/cenmin/v5/parts
SUPER="$CB/super-coloros-v43.simg"
REL="$CB/release-coloros-v43"
OUT=$(mktemp -d /home/cenmin/v43-verify.XXXXXX)
M="$OUT/mnt"
mkdir -p "$M/system" "$M/system_ext" "$M/product" "$M/vendor" "$M/odm" "$M/my_product" "$M/my_stock"

cleanup(){
  for d in system system_ext product vendor odm my_product my_stock; do
    umount "$M/$d" 2>/dev/null || true
  done
  rm -rf -- "$OUT"
}
trap cleanup EXIT

check_absent(){
  if [ -e "$1" ]; then echo "unexpected path: $1" >&2; exit 1; fi
}
check_present(){
  if [ ! -e "$1" ]; then echo "missing path: $1" >&2; exit 1; fi
}
check_hash(){
  local got
  got=$(sha256sum "$1" | cut -d' ' -f1)
  if [ "$got" != "$2" ]; then echo "hash mismatch: $1 $got != $2" >&2; exit 1; fi
}

echo "== unpack super =="
RAW="$OUT/super.raw"
PARTS="$OUT/parts"
mkdir -p "$PARTS"
"$OT/simg2img" "$SUPER" "$RAW"
"$OT/lpunpack" "$RAW" "$PARTS" >/dev/null

echo "== compare partitions =="
cmp "$PARTS/system_a.img" "$B/system-v43.erofs"
cmp "$PARTS/system_ext_a.img" "$B/system_ext_v43.erofs"
cmp "$PARTS/product_a.img" "$B/product_v43.erofs"
cmp "$PARTS/vendor_a.img" "$B/vendor_a_v43.img"
cmp "$PARTS/odm_a.img" "$B/odm_v43.erofs"
cmp "$PARTS/my_product_a.img" "$B/my_product_a_v43.erofs"
cmp "$PARTS/my_stock_a.img" "$B/my_stock_a_v43.erofs"
cmp "$PARTS/my_manifest_a.img" "$P/my_manifest_a.img"
cmp "$PARTS/my_region_a.img" "$P/my_region_a.img"
cmp "$PARTS/my_engineering_a.img" "$P/my_engineering_a.img"
cmp "$PARTS/my_heytap_a.img" "$P/my_heytap_a.img"
cmp "$PARTS/my_carrier_a.img" "$P/my_carrier_a.img"
cmp "$PARTS/my_bigball_a.img" "$P/my_bigball_a.img"

echo "== filesystems =="
/home/cenmin/toolchain/erofs-install/bin/fsck.erofs "$B/system-v43.erofs"
/home/cenmin/toolchain/erofs-install/bin/fsck.erofs "$B/system_ext_v43.erofs"
/home/cenmin/toolchain/erofs-install/bin/fsck.erofs "$B/product_v43.erofs"
/home/cenmin/toolchain/erofs-install/bin/fsck.erofs "$B/odm_v43.erofs"
/home/cenmin/toolchain/erofs-install/bin/fsck.erofs "$B/my_product_a_v43.erofs"
/home/cenmin/toolchain/erofs-install/bin/fsck.erofs "$B/my_stock_a_v43.erofs"
e2fsck -fn "$B/vendor_a_v43.img"

echo "== mount =="
mount -t erofs -o loop,ro "$B/system-v43.erofs" "$M/system"
mount -t erofs -o loop,ro "$B/system_ext_v43.erofs" "$M/system_ext"
mount -t erofs -o loop,ro "$B/product_v43.erofs" "$M/product"
mount -o loop,ro "$B/vendor_a_v43.img" "$M/vendor"
mount -t erofs -o loop,ro "$B/odm_v43.erofs" "$M/odm"
mount -t erofs -o loop,ro "$B/my_product_a_v43.erofs" "$M/my_product"
mount -t erofs -o loop,ro "$B/my_stock_a_v43.erofs" "$M/my_stock"

echo "== system/graphics =="
check_hash "$M/system/system/bin/surfaceflinger" 44482c704adf3f661f688695a37655150bc8c4851b360a06f0ffb03beb73dcac
getfattr -d -m - "$M/system/system/etc/init/gaokun3-v43.rc"
grep -q "org.codeaurora.ims" "$M/system/system/etc/sysconfig/gaokun3-components.xml"
grep -q "com.coloros.findmyphone" "$M/system/system/etc/sysconfig/gaokun3-components.xml"
grep -q "com.oplus.find.provider.FindProvider" "$M/system/system/etc/sysconfig/gaokun3-components.xml"

echo "== zygote/ABI/density =="
for f in "$M/system/system/build.prop" "$M/vendor/build.prop" "$M/odm/build.prop" "$M/my_product/build.prop"; do
  grep -q "^ro.zygote=zygote64_32$" "$f"
done
for f in "$M/odm/build.prop" "$M/my_product/build.prop"; do
  grep -q "^ro.sf.lcd_density=240$" "$f"
done
[ -x "$M/system/system/bin/app_process32" ]
[ -x "$M/system/system/bin/app_process64" ]
[ -L "$M/system/system/lib/libc.so" ]
[ -L "$M/system/system/lib64/libc.so" ]
if grep -Rqs "^ro.sf.lcd_density=420$" "$M/system/system" "$M/vendor" "$M/odm" "$M/my_product"; then
  echo "stale 420 density found" >&2
  exit 1
fi

echo "== vendor policy =="
check_hash "$M/vendor/bin/hw/android.hardware.light-service.gaokun3" e02556898c6ba10ed41080b76425b43a11f14dfe492dbb8bfd0492f70f8257dc
python3 - "$M/vendor/bin/hw/android.hardware.light-service.gaokun3" <<'PY'
from pathlib import Path
import struct, sys
p=Path(sys.argv[1]); d=p.read_bytes()
assert struct.unpack_from('<I', d, 0x393d4)[0] == 0x39400048
print('light insn verified')
PY
grep -q "android.hardware.sensor.light" "$M/vendor/etc/permissions/gaokun3-unavailable-features.xml"
grep -q "android.hardware.telephony.ims" "$M/vendor/etc/permissions/gaokun3-unavailable-features.xml"
grep -q "android.hardware.nfc" "$M/vendor/etc/permissions/gaokun3-unavailable-features.xml"
getfattr -d -m - "$M/vendor/etc/permissions/gaokun3-unavailable-features.xml"
grep -A1 "^service android-hardware-media-c2-v4l2-hal " "$M/vendor/etc/init/android.hardware.media.c2-service-v4l2.rc" | grep -q "^    disabled$"
check_absent "$M/vendor/etc/vintf/manifest/android.hardware.media.c2-service-v4l2.xml"
check_absent "$M/vendor/etc/init/gk3-capture.rc"
check_absent "$M/vendor/bin/gk3-capture.sh"
check_absent "$M/vendor/bin/v38r3_dump.sh"
check_absent "$M/vendor/bin/v40_dump.sh"
if grep -RqsE "gk3-capture|v38r3_dump|v40_dump" "$M/vendor/etc/init" "$M/vendor/bin"; then
  echo "stale capture probe found" >&2
  exit 1
fi

echo "== donor isolation =="
check_absent "$M/system_ext/priv-app/ims"
check_absent "$M/system_ext/app/ImsDataChannelService"
check_absent "$M/system_ext/app/OTA"
check_absent "$M/system_ext/bin/cotad"
check_absent "$M/my_stock/priv-app/OplusBootReg"
check_absent "$M/my_stock/priv-app/Cota"
check_absent "$M/my_stock/app/RomUpdate"
check_absent "$M/my_product/etc/permissions/android.hardware.sensor.light.xml"

echo "== display/WFD =="
check_present "$M/product/etc/displayconfig/default.xml"
check_present "$M/product/etc/displayconfig/display_id_0.xml"
grep -q "<width>1600</width>" "$M/product/etc/displayconfig/default.xml"
grep -q "<height>2560</height>" "$M/product/etc/displayconfig/default.xml"
grep -q "^persist.debug.wfd.enable=0$" "$M/system/system/build.prop"
check_absent "$M/vendor/etc/permissions/android.hardware.wifi.direct.xml"

echo "== release =="
zstd -t "$REL/super.img.zst"
sha256sum "$REL/super.img.zst" "$REL/boot.img" "$SUPER"
echo V43_VERIFIED
