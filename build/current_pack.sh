#!/usr/bin/env bash
# 从 current/manifest.json 出 super，不再手写分区列表。
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OT=${GK3_OTATOOLS:-$SCRIPT_DIR/../tools/otatools/bin}
PUB=${GK3_PUBLISH:-/mnt/d/gaokun-coloros-release/latest}
ROOT=/home/cenmin/coloros-build/current

SUPER=$ROOT/release/super.img
ZB=$ROOT/zb
mkdir -p "$(dirname "$SUPER")" "$ZB"

echo '== 闸门复检（出包前必跑）'
bash "$SCRIPT_DIR/current_verify.sh" || { echo 'PACK_ABORTED: verify failed'; exit 1; }

python3 - "$ROOT" "$SUPER" "$ZB" "$OT" <<'PY'
import json, os, shutil, subprocess, sys
root, super_out, zb, OT = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
man = json.load(open(os.path.join(root, 'manifest.json')))
names = ['system', 'system_ext', 'product', 'vendor', 'odm', 'my_product', 'my_stock',
         'my_manifest', 'my_region', 'my_engineering', 'my_heytap', 'my_carrier', 'my_bigball']
lim = 21473689088
F = [man['parts'][n]['path'] for n in names]
total = sum(os.path.getsize(f) for f in F)
print(f'per-slot: {total}  total2: {total*2}  limit: {lim}')
assert total * 2 < lim, 'TOO_BIG'

cmd = [f'{OT}/lpmake', '-S', '-F', '-d', '21474836480', '-m', '65536', '-s', '3', '--virtual-ab',
       '-b', '4096', '-g', 'gaokun3_dynamic_partitions_a:21473689088']
for slot in ('a', 'b'):
    for i, n in enumerate(names):
        f = F[i] if slot == 'a' else os.path.join(zb, f'{n}_b.img')
        if slot == 'b' and not os.path.exists(f):
            open(f, 'wb').truncate(os.path.getsize(F[i]))
        cmd += ['-p', f'{n}_{slot}:none:{os.path.getsize(f)}:gaokun3_dynamic_partitions_a']
for i, n in enumerate(names):
    cmd += ['-i', f'{n}_a={F[i]}']
for i, n in enumerate(names):
    cmd += ['-i', f'{n}_b={os.path.join(zb, n + "_b.img")}']
cmd += ['-o', super_out]
if os.path.exists(super_out):
    os.remove(super_out)
log = open(os.path.join(root, 'logs', 'pack.log'), 'w')
rc = subprocess.call(cmd, stdout=log, stderr=subprocess.STDOUT)
log.close()
if rc != 0:
    print(open(os.path.join(root, 'logs', 'pack.log')).read()[-2000:])
    sys.exit(rc)
print('super:', super_out, os.path.getsize(super_out))
PY

echo '== 发布到 latest（Windows 侧）'

mkdir -p "$PUB"
cp "$SUPER" "$PUB/super.img"
cd "$PUB"
sha256sum super.img > super.img.sha256.txt
echo "bytes: $(stat -c%s super.img)" >> super.img.sha256.txt
echo "built-from: current/manifest.json ($(python3 -c "import json;print(json.load(open('/home/cenmin/coloros-build/current/manifest.json'))['generated'])"))" >> super.img.sha256.txt
cat super.img.sha256.txt
echo CURRENT_PACK_DONE
