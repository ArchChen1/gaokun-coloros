#!/bin/bash
set -euo pipefail

CB=/home/cenmin/coloros-build
WORK=/home/cenmin/v43-build
OUT="$CB/v43"
EDIT=/mnt/e/gaokun-coloros/coloros-port/scripts/v43_edit_tree.py
SF_PATCH=/mnt/e/gaokun-coloros/coloros-port/scripts/patch_sf_waits.py
MKFS=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
PARTS=/home/cenmin/v5/parts

rm -rf -- "$WORK"
mkdir -p "$WORK" "$OUT"
trap 'rm -rf -- "$WORK"' EXIT

extract_erofs() {
  local img="$1" tree="$2" mnt="$3"
  mkdir -p "$tree" "$mnt"
  mount -t erofs -o loop,ro "$img" "$mnt"
  rsync -aHAX --numeric-ids "$mnt"/ "$tree"/
  umount "$mnt"
}

extract_ext4() {
  local img="$1" tree="$2" mnt="$3"
  mkdir -p "$tree" "$mnt"
  mount -o loop,ro "$img" "$mnt"
  rsync -aHAX --numeric-ids "$mnt"/ "$tree"/
  umount "$mnt"
}

build_erofs() {
  local tree="$1" out="$2" uuid="$3" name="$4" cluster="$5"
  rm -f "$out"
  "$MKFS" -zlz4 -b4096 -C"$cluster" -U "$uuid" -L "$name" -T 1793807531 "$out" "$tree"
  "$FSCK" "$out"
  sha256sum "$out"
}

echo '== system =='
rsync -aHAX --numeric-ids /home/cenmin/v38-system/tree/ "$WORK/system"/
python3 -I "$EDIT" system "$WORK/system"
python3 -I "$SF_PATCH" "$WORK/system/system/bin/surfaceflinger" "$WORK/surfaceflinger.v43"
cat "$WORK/surfaceflinger.v43" > "$WORK/system/system/bin/surfaceflinger"
rm -f "$WORK/surfaceflinger.v43"
build_erofs "$WORK/system" "$OUT/system-v43.erofs" \
  8e526587-69d7-562d-a908-a83699912a48 system 65536

echo '== system_ext =='
extract_erofs "$PARTS/system_ext_a.img" "$WORK/system_ext" "$WORK/mnt-system_ext"
python3 -I "$EDIT" system_ext "$WORK/system_ext"
build_erofs "$WORK/system_ext" "$OUT/system_ext_v43.erofs" \
  2bfe47df-c3ff-55f1-a38e-9d5072a9ce45 system_ext 65536

echo '== product =='
extract_erofs "$PARTS/product_a.img" "$WORK/product" "$WORK/mnt-product"
python3 -I "$EDIT" product "$WORK/product"
build_erofs "$WORK/product" "$OUT/product_v43.erofs" \
  34f45120-7aa2-511e-b4ca-48172f834314 product 65536

echo '== odm =='
extract_erofs "$CB/v38/odm_v38.img" "$WORK/odm" "$WORK/mnt-odm"
python3 -I "$EDIT" odm "$WORK/odm"
build_erofs "$WORK/odm" "$OUT/odm_v43.erofs" \
  2f2ea3d1-c76b-5f2c-b99b-45ba6421cc21 odm 1048576

echo '== my_product =='
extract_erofs "$CB/v39/my_product_a_v39.img" "$WORK/my_product" "$WORK/mnt-my_product"
python3 -I "$EDIT" my_product "$WORK/my_product"
build_erofs "$WORK/my_product" "$OUT/my_product_a_v43.erofs" \
  d133458d-0e5d-58f3-b521-b1bedbb17daf my_product 65536

echo '== my_stock =='
extract_erofs "$PARTS/my_stock_a.img" "$WORK/my_stock" "$WORK/mnt-my_stock"
python3 -I "$EDIT" my_stock "$WORK/my_stock"
build_erofs "$WORK/my_stock" "$OUT/my_stock_a_v43.erofs" \
  465883b9-8c6c-5d53-a543-7b117af90eaa my_stock 1048576

echo '== vendor =='
cp -f "$CB/v38/vendor_a_v41.img" "$OUT/vendor_a_v43.img"
mkdir -p "$WORK/mnt-vendor"
mount -o loop,rw "$OUT/vendor_a_v43.img" "$WORK/mnt-vendor"
python3 -I "$EDIT" vendor "$WORK/mnt-vendor"
umount "$WORK/mnt-vendor"
set +e
e2fsck -fy "$OUT/vendor_a_v43.img" > "$WORK/e2fsck-vendor.log" 2>&1
rc=$?
set -e
if [ "$rc" -gt 1 ]; then cat "$WORK/e2fsck-vendor.log"; exit "$rc"; fi
sha256sum "$OUT/vendor_a_v43.img"

echo '== v43 partitions built =='
ls -lh "$OUT"