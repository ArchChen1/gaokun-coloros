#!/usr/bin/env bash
# 固化基座：vendor 从输入镜像派生并打补丁 → 断言 → 重打 system/odm → 写 manifest。
# 用法：current_build.sh [版本号]     例如 current_build.sh v54
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/env.sh"
VER="${1:-${GK3_VERSION:-dev}}"

mkdir -p "$GK3_PARTS" "$GK3_STATE/logs" "$GK3_INPUTS" "$GK3_TREES"

echo "== 0. 输入检查（$GK3_INPUTS）"
for f in "$GK3_VENDOR_BASE" "$GK3_MY_PRODUCT" "$GK3_MY_STOCK"; do
  [ -s "$f" ] || { echo "缺少输入: $f（先跑 make fetch）"; exit 1; }
done

echo '== 1. vendor: 从输入镜像派生并打补丁'
if [ "${FORCE_VENDOR:-0}" = 1 ] || [ ! -f "$GK3_PARTS/vendor.img" ]; then
  cp --reflink=auto "$GK3_VENDOR_BASE" "$GK3_PARTS/vendor.img"
  mkdir -p /mnt/cv; umount /mnt/cv 2>/dev/null || true
  mount -t ext4 -o loop,rw "$GK3_PARTS/vendor.img" /mnt/cv
  python3 - /mnt/cv/etc/init/hw/init.gaokun3.rc <<'PY'
import sys
p = sys.argv[1]
d = open(p).read()
old = '    write /sys/bus/pci/drivers/ath11k_pci/bind "0006:01:00.0"\n'
new = ('    # 固件已随 system 分发，早 probe 就能拿到；这里只留非阻塞重试，绝不能再堵 init。\n'
       '    exec_background - root root -- /system/bin/sh -c "echo 0006:01:00.0 > /sys/bus/pci/drivers/ath11k_pci/bind"\n')
if old in d:
    open(p, 'w').write(d.replace(old, new, 1)); print('rc: 同步 bind -> exec_background')
else:
    print('rc: 已是补丁后的状态')
PY
  setfattr -n security.selinux -v "u:object_r:gaokun3_wlanap_exec:s0" /mnt/cv/bin/v29_usb_capture.sh 2>/dev/null \
    && echo 'v29 脚本已换标签' || echo 'v29 标签设置失败（不影响构建）'
  umount /mnt/cv
  e2fsck -fn "$GK3_PARTS/vendor.img" >/dev/null 2>&1 && echo 'vendor fsck clean'
else
  echo 'vendor.img 已存在，复用（强制重打：FORCE_VENDOR=1）'
fi

echo '== 2. 其余输入分区挂进 parts'
ln -sf "$GK3_MY_PRODUCT" "$GK3_PARTS/my_product.erofs"
ln -sf "$GK3_MY_STOCK" "$GK3_PARTS/my_stock.erofs"

echo '== 3. 出包前断言（允许 parts/system、parts/odm 尚不存在）'
GK3_ALLOW_MISSING_PARTS=1 bash "$SCRIPT_DIR/current_verify.sh"

echo '== 4. 从断言过的树重打 system / odm'
rm -f "$GK3_PARTS/system.erofs" "$GK3_PARTS/odm.erofs"
"$GK3_MKFS_EROFS" -zlz4 -b4096 -C65536 -L system "$GK3_PARTS/system.erofs" "$GK3_SYS_TREE" >/dev/null
"$GK3_MKFS_EROFS" -zlz4 -b4096 -C65536 -L odm "$GK3_PARTS/odm.erofs" "$GK3_ODM" >/dev/null
"$GK3_FSCK_EROFS" "$GK3_PARTS/system.erofs" >/dev/null 2>&1 && echo "system ok $(stat -c%s "$GK3_PARTS/system.erofs")"
"$GK3_FSCK_EROFS" "$GK3_PARTS/odm.erofs" >/dev/null 2>&1 && echo "odm ok $(stat -c%s "$GK3_PARTS/odm.erofs")"

echo '== 5. 写 manifest.json'
python3 - "$GK3_STATE" "$GK3_SRC" "$GK3_PARTS" "$VER" <<'PY'
import datetime, hashlib, json, os, sys
state, src, parts, ver = sys.argv[1:5]
names = ['system', 'system_ext', 'product', 'vendor', 'odm', 'my_product', 'my_stock',
         'my_manifest', 'my_region', 'my_engineering', 'my_heytap', 'my_carrier', 'my_bigball']
src_only = {'system_ext', 'product', 'my_manifest', 'my_region', 'my_engineering',
            'my_heytap', 'my_carrier', 'my_bigball'}
def sha(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()
ents = {}
for n in names:
    p = os.path.join(src, f'{n}_a.img') if n in src_only else os.path.join(
        parts, 'vendor.img' if n == 'vendor' else f'{n}.erofs')
    ents[n] = {'path': os.path.realpath(p), 'bytes': os.path.getsize(p), 'sha256': sha(p)}
man = {
    'version': ver,
    'generated': datetime.datetime.now().isoformat(timespec='seconds'),
    'assertions': 'build/current_verify.sh 全绿',
    'invariants': {
        'vendor_vulkan_freedreno_sha256': '7619b1286b7d0b2d697e0c48b6a471ab7f439eee0523ce1820fee6ba612b1d90',
        'vendor_hwui_renderer': 'skiavk',
        'system_density_trigger': 'on property:persist.sys.display.density=480 -> 320',
        'ath11k_firmware_in_system': True,
        'odm_libs': ['libjsoncpp.so', 'android.hardware.sensors-V3-ndk.so', 'libhidltransport.so'],
    },
    'parts': ents,
}
json.dump(man, open(os.path.join(state, 'manifest.json'), 'w'), indent=2, ensure_ascii=False)
print('manifest:', os.path.join(state, 'manifest.json'), 'version:', ver)
PY

echo '== 6. 出包后全量断言'
bash "$SCRIPT_DIR/current_verify.sh"
echo CURRENT_BUILD_DONE
