#!/bin/bash
set -euo pipefail
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
CB=/home/cenmin/coloros-build
P=/home/cenmin/v5/parts
SUPER="$CB/super-coloros-v38r3.simg"
OUT=$(mktemp -d /home/cenmin/v38r3-verify.XXXXXX)
RAW="$OUT/super.raw"
PARTS="$OUT/parts"
mkdir -p "$PARTS"

echo "== zstd =="
zstd -t "$CB/release-coloros-v38r3/super.img.zst"

echo "== unpack =="
"$OT/simg2img" "$SUPER" "$RAW"
"$OT/lpunpack" "$RAW" "$PARTS" >/dev/null

echo "== compare =="
cmp "$PARTS/system_a.img" "$CB/v38/system-v38.erofs"
cmp "$PARTS/system_ext_a.img" "$P/system_ext_a.img"
cmp "$PARTS/product_a.img" "$P/product_a.img"
cmp "$PARTS/vendor_a.img" "$CB/v38/vendor_a_v38r3.img"
cmp "$PARTS/odm_a.img" "$CB/v38/odm_v38.img"
cmp "$PARTS/my_product_a.img" "$P/my_product_a.img"
cmp "$PARTS/my_stock_a.img" "$P/my_stock_a.img"
cmp "$PARTS/my_manifest_a.img" "$P/my_manifest_a.img"
cmp "$PARTS/my_region_a.img" "$P/my_region_a.img"
cmp "$PARTS/my_engineering_a.img" "$P/my_engineering_a.img"
cmp "$PARTS/my_heytap_a.img" "$P/my_heytap_a.img"
cmp "$PARTS/my_carrier_a.img" "$P/my_carrier_a.img"
cmp "$PARTS/my_bigball_a.img" "$P/my_bigball_a.img"

echo "== vendor fsck =="
e2fsck -fn "$CB/v38/vendor_a_v38r3.img"

echo "== rc/probe =="
debugfs -R 'cat /etc/init/hw/init.gaokun3.rc' "$CB/v38/vendor_a_v38r3.img" 2>/dev/null | grep -A16 'v38r3'
debugfs -R 'stat /bin/v38r3_dump.sh' "$CB/v38/vendor_a_v38r3.img" 2>/dev/null || true

echo "== hashes =="
sha256sum "$SUPER" "$CB/release-coloros-v38r3/super.img.zst" "$CB/v38/vendor_a_v38r3.img"
echo "VERIFY_DIR=$OUT"
echo V38R3_VERIFIED
