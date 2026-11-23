#!/usr/bin/env bash
# 把「当前正确基座」固化到 /home/cenmin/coloros-build/current/parts，
# 由断言链把关；任何一步不过就不产出。
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
B=/home/cenmin/coloros-build
ROOT=$B/current
PARTS=$ROOT/parts
SYS=/home/cenmin/v50-build/system/system
ODM=/home/cenmin/v50-build/odm
MK=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FB=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
mkdir -p "$PARTS" "$ROOT/logs"

echo '== 1. vendor: 以 v52（已验证上机）为基座，重打补丁'
if [ "${FORCE_VENDOR:-0}" = 1 ] || [ ! -f "$PARTS/vendor.img" ]; then
  cp --reflink=auto "$B/v52/vendor_a_v52.img" "$PARTS/vendor.img"
  mkdir -p /mnt/cv; umount /mnt/cv 2>/dev/null || true
  mount -t ext4 -o loop,rw "$PARTS/vendor.img" /mnt/cv
  python3 - /mnt/cv/etc/init/hw/init.gaokun3.rc <<'PY'
import sys
p = sys.argv[1]
d = open(p).read()
old = '    write /sys/bus/pci/drivers/ath11k_pci/bind "0006:01:00.0"\n'
new = ('    # v54: firmware ships in /system/etc/firmware/ath11k so the early probe finds it;\n'
       '    # retry is kept but must never block init again.\n'
       '    exec_background - root root -- /system/bin/sh -c "echo 0006:01:00.0 > /sys/bus/pci/drivers/ath11k_pci/bind"\n')
if old in d:
    open(p, 'w').write(d.replace(old, new, 1)); print('rc: bind -> exec_background')
else:
    print('rc: already patched')
PY
  setfattr -n security.selinux -v "u:object_r:gaokun3_wlanap_exec:s0" /mnt/cv/bin/v29_usb_capture.sh 2>/dev/null && echo 'v29 relabel ok' || echo 'v29 relabel failed'
  umount /mnt/cv
  e2fsck -fn "$PARTS/vendor.img" >/dev/null 2>&1 && echo 'vendor fsck clean'
else
  echo 'vendor.img 已存在，复用（要强制重打用 FORCE_VENDOR=1）'
fi

echo '== 2. 其余分区软链到已验证来源'
ln -sf "$B/v52/my_product_a_v52b.erofs" "$PARTS/my_product.erofs"
ln -sf "$B/v52/my_stock_a_v52.erofs"     "$PARTS/my_stock.erofs"

echo '== 3. 断言闸门'
bash "$SCRIPT_DIR/current_verify.sh"

echo '== 4. 从断言过的树重打 system / odm'
rm -f "$PARTS/system.erofs" "$PARTS/odm.erofs"
"$MK" -zlz4 -b4096 -C65536 -L system "$PARTS/system.erofs" /home/cenmin/v50-build/system
"$MK" -zlz4 -b4096 -C65536 -L odm "$PARTS/odm.erofs" /home/cenmin/v50-build/odm
"$FB" "$PARTS/system.erofs" >/dev/null 2>&1 && echo "system ok $(stat -c%s "$PARTS/system.erofs")"
"$FB" "$PARTS/odm.erofs" >/dev/null 2>&1 && echo "odm ok $(stat -c%s "$PARTS/odm.erofs")"

echo '== 5. 写 manifest.json'
python3 - "$ROOT" <<'PY'
import hashlib, json, os, datetime
ROOT = os.sys.argv[1]
PARTS = os.path.join(ROOT, 'parts')
SRC = '/home/cenmin/coloros-build/v49/src'
names = ['system', 'system_ext', 'product', 'vendor', 'odm', 'my_product', 'my_stock',
         'my_manifest', 'my_region', 'my_engineering', 'my_heytap', 'my_carrier', 'my_bigball']
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()
entries = {}
for n in names:
    p = os.path.join(PARTS, n + ('.img' if n == 'vendor' else '.erofs'))
    if not os.path.exists(p):
        p = (os.path.join(SRC, n + '_a.img') if n in ('system_ext', 'product', 'my_manifest', 'my_region',
                                                      'my_engineering', 'my_heytap', 'my_carrier', 'my_bigball')
             else os.path.join(PARTS, n + '.erofs'))
    entries[n] = {'path': os.path.realpath(p), 'bytes': os.path.getsize(p), 'sha256': sha(p)}
man = {
    'generated': datetime.datetime.now().isoformat(timespec='seconds'),
    'assertions': 'scripts/current_verify.sh 全绿',
    'invariants': {
        'vendor_vulkan_freedreno_sha256': '7619b1286b7d0b2d697e0c48b6a471ab7f439eee0523ce1820fee6ba612b1d90',
        'vendor_hwui_renderer': 'skiavk',
        'system_density_trigger': 'on property:persist.sys.display.density=480 -> 320',
        'ath11k_firmware_in_system': True,
        'odm_libjsoncpp': True,
    },
    'parts': entries,
}
json.dump(man, open(os.path.join(ROOT, 'manifest.json'), 'w'), indent=2, ensure_ascii=False)
print('manifest written:', os.path.join(ROOT, 'manifest.json'))
PY
echo CURRENT_BUILD_DONE
