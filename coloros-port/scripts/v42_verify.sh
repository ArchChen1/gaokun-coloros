#!/bin/bash
set -euo pipefail
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
CB=/home/cenmin/coloros-build
P=/home/cenmin/v5/parts
SYS="$CB/v42/system-v42.erofs"
V="$CB/v38/vendor_a_v41.img"
MYPROD="$CB/v39/my_product_a_v39.img"
SUPER="$CB/super-coloros-v42.simg"
OUT=$(mktemp -d /home/cenmin/v42-verify.XXXXXX)
RAW="$OUT/super.raw"
PARTS="$OUT/parts"
mkdir -p "$PARTS"

echo "== zstd =="
zstd -t "$CB/release-coloros-v42/super.img.zst"
echo "== unpack =="
"$OT/simg2img" "$SUPER" "$RAW"
"$OT/lpunpack" "$RAW" "$PARTS" >/dev/null
echo "== compare =="
cmp "$PARTS/system_a.img" "$SYS"
cmp "$PARTS/system_ext_a.img" "$P/system_ext_a.img"
cmp "$PARTS/product_a.img" "$P/product_a.img"
cmp "$PARTS/vendor_a.img" "$V"
cmp "$PARTS/odm_a.img" "$CB/v38/odm_v38.img"
cmp "$PARTS/my_product_a.img" "$MYPROD"
cmp "$PARTS/my_stock_a.img" "$P/my_stock_a.img"
cmp "$PARTS/my_manifest_a.img" "$P/my_manifest_a.img"
cmp "$PARTS/my_region_a.img" "$P/my_region_a.img"
cmp "$PARTS/my_engineering_a.img" "$P/my_engineering_a.img"
cmp "$PARTS/my_heytap_a.img" "$P/my_heytap_a.img"
cmp "$PARTS/my_carrier_a.img" "$P/my_carrier_a.img"
cmp "$PARTS/my_bigball_a.img" "$P/my_bigball_a.img"

echo "== fsck =="
/home/cenmin/toolchain/erofs-install/bin/fsck.erofs "$SYS"
/home/cenmin/toolchain/erofs-install/bin/fsck.erofs "$MYPROD"
e2fsck -fn "$V"

echo "== surfaceflinger =="
dump.erofs --path /system/bin/surfaceflinger "$SYS" 2>/dev/null | head -10
mkdir -p /mnt/v42-sf-check
mount -t erofs -o loop,ro "$SYS" /mnt/v42-sf-check
getfattr -d -m - /mnt/v42-sf-check/system/bin/surfaceflinger 2>&1 | tail -2
sha256sum /mnt/v42-sf-check/system/bin/surfaceflinger /home/cenmin/v41-surfaceflinger
umount /mnt/v42-sf-check

echo "== hashes =="
sha256sum "$SUPER" "$CB/release-coloros-v42/super.img.zst" "$SYS" "$V" "$MYPROD"
echo "VERIFY_DIR=$OUT"
echo V42_VERIFIED
