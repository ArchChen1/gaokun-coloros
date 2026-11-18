set -u
OT=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin
CB=/home/cenmin/coloros-build
V5=$CB/vendor-gaokun-v5.img
SYS5=/home/cenmin/v5/system-v5.erofs
RAW=/home/cenmin/v4c-super.raw
PARTS=/home/cenmin/v5/parts
OUT=$CB/super-coloros-v5.simg

echo "########## 1. extract the 11 unchanged partitions from v4c raw ##########"
mkdir -p $PARTS
if [ ! -s $PARTS/odm_a.img ]; then
  time $OT/lpunpack "$RAW" $PARTS 2>&1 | tail -3
fi
ls -l $PARTS/ | head -20
echo "file count: $(ls $PARTS | wc -l)"

echo
echo "########## 2. sizes (must match v4c exactly for group budget) ##########"
for n in system system_ext product odm my_product my_stock my_manifest my_region my_engineering my_heytap my_carrier my_bigball; do
  a=$(stat -c%s $PARTS/${n}_a.img 2>/dev/null || echo MISSING)
  printf '  %-16s %s\n' "$n" "$a"
done
echo "  -- new system --"
ls -l $SYS5
echo "  -- old system (v4c parts) --"
stat -c%s $PARTS/system_a.img
echo "  delta(new-old) = $(( $(stat -c%s $SYS5) - $(stat -c%s $PARTS/system_a.img) )) bytes"
echo "  -- vendor --"
ls -l $V5

echo
echo "########## 3. build super ##########"
$OT/lpmake -S -F -d 12884901888 -m 65536 -s 3 --virtual-ab -b 4096 \
  -g gaokun3_dynamic_partitions_a:12683575296 \
  -p system_a:none:$(stat -c%s $SYS5):gaokun3_dynamic_partitions_a \
  -p system_ext_a:none:$(stat -c%s $PARTS/system_ext_a.img):gaokun3_dynamic_partitions_a \
  -p product_a:none:$(stat -c%s $PARTS/product_a.img):gaokun3_dynamic_partitions_a \
  -p vendor_a:none:$(stat -c%s $V5):gaokun3_dynamic_partitions_a \
  -p odm_a:none:$(stat -c%s $PARTS/odm_a.img):gaokun3_dynamic_partitions_a \
  -p my_product_a:none:$(stat -c%s $PARTS/my_product_a.img):gaokun3_dynamic_partitions_a \
  -p my_stock_a:none:$(stat -c%s $PARTS/my_stock_a.img):gaokun3_dynamic_partitions_a \
  -p my_manifest_a:none:$(stat -c%s $PARTS/my_manifest_a.img):gaokun3_dynamic_partitions_a \
  -p my_region_a:none:$(stat -c%s $PARTS/my_region_a.img):gaokun3_dynamic_partitions_a \
  -p my_engineering_a:none:$(stat -c%s $PARTS/my_engineering_a.img):gaokun3_dynamic_partitions_a \
  -p my_heytap_a:none:$(stat -c%s $PARTS/my_heytap_a.img):gaokun3_dynamic_partitions_a \
  -p my_carrier_a:none:$(stat -c%s $PARTS/my_carrier_a.img):gaokun3_dynamic_partitions_a \
  -p my_bigball_a:none:$(stat -c%s $PARTS/my_bigball_a.img):gaokun3_dynamic_partitions_a \
  -i system_a=$SYS5 \
  -i system_ext_a=$PARTS/system_ext_a.img -i product_a=$PARTS/product_a.img \
  -i vendor_a="$V5" -i odm_a=$PARTS/odm_a.img \
  -i my_product_a=$PARTS/my_product_a.img -i my_stock_a=$PARTS/my_stock_a.img \
  -i my_manifest_a=$PARTS/my_manifest_a.img -i my_region_a=$PARTS/my_region_a.img \
  -i my_engineering_a=$PARTS/my_engineering_a.img -i my_heytap_a=$PARTS/my_heytap_a.img \
  -i my_carrier_a=$PARTS/my_carrier_a.img -i my_bigball_a=$PARTS/my_bigball_a.img \
  -o "$OUT" 2>&1 | tail -6
echo "lpmake rc=$?"
ls -l "$OUT"
echo SUPER_BUILT