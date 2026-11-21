#!/bin/bash
set -euo pipefail
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
CB=/home/cenmin/coloros-build
P=/home/cenmin/v5/parts
SUPER="$CB/super-coloros-v39.simg"
MYPROD="$CB/v39/my_product_a_v39.img"
OUT=$(mktemp -d /home/cenmin/v39-verify.XXXXXX)
RAW="$OUT/super.raw"
PARTS="$OUT/parts"
mkdir -p "$PARTS"

echo "== zstd =="
zstd -t "$CB/release-coloros-v39/super.img.zst"

echo "== unpack =="
"$OT/simg2img" "$SUPER" "$RAW"
"$OT/lpunpack" "$RAW" "$PARTS" >/dev/null

echo "== compare =="
cmp "$PARTS/system_a.img" "$CB/v38/system-v38.erofs"
cmp "$PARTS/system_ext_a.img" "$P/system_ext_a.img"
cmp "$PARTS/product_a.img" "$P/product_a.img"
cmp "$PARTS/vendor_a.img" "$CB/v38/vendor_a_v38r3.img"
cmp "$PARTS/odm_a.img" "$CB/v38/odm_v38.img"
cmp "$PARTS/my_product_a.img" "$MYPROD"
cmp "$PARTS/my_stock_a.img" "$P/my_stock_a.img"
cmp "$PARTS/my_manifest_a.img" "$P/my_manifest_a.img"
cmp "$PARTS/my_region_a.img" "$P/my_region_a.img"
cmp "$PARTS/my_engineering_a.img" "$P/my_engineering_a.img"
cmp "$PARTS/my_heytap_a.img" "$P/my_heytap_a.img"
cmp "$PARTS/my_carrier_a.img" "$P/my_carrier_a.img"
cmp "$PARTS/my_bigball_a.img" "$P/my_bigball_a.img"

echo "== erofs fsck =="
/home/cenmin/toolchain/erofs-install/bin/fsck.erofs "$CB/v38/system-v38.erofs"
/home/cenmin/toolchain/erofs-install/bin/fsck.erofs "$MYPROD"

echo "== my_product feature/xattr =="
dump.erofs --path /etc/permissions/oplus.features.connectivity.xml "$MYPROD" 2>/dev/null | head -10
if dump.erofs --path /etc/permissions/oplus.features.connectivity.xml "$MYPROD" 2>/dev/null | grep -q 'Xattr size: 16'; then
  echo 'feature xattr OK'
else
  echo 'feature xattr missing' >&2
  exit 1
fi
mkdir -p /mnt/v39-final-check
mount -t erofs -o loop,ro "$MYPROD" /mnt/v39-final-check
if grep -q 'oplus.software.wlan.smart_antenna' /mnt/v39-final-check/etc/permissions/oplus.features.connectivity.xml; then
  echo 'smart_antenna still present' >&2
  umount /mnt/v39-final-check
  exit 1
fi
getfattr -d -m - /mnt/v39-final-check/etc/permissions/oplus.features.connectivity.xml 2>&1 | tail -2
umount /mnt/v39-final-check

echo "== hashes =="
sha256sum "$SUPER" "$CB/release-coloros-v39/super.img.zst" "$MYPROD"
echo "VERIFY_DIR=$OUT"
echo V39_VERIFIED
