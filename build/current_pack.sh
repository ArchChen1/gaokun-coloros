#!/usr/bin/env bash
# 从 manifest.json 出 super 并发布。分区清单永远来自 manifest，不手写。
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/env.sh"

SUPER_DIR="$GK3_STATE/release"
ZB="$GK3_STATE/zb"
mkdir -p "$SUPER_DIR" "$ZB"

echo '== 出包前断言（必跑）'
bash "$SCRIPT_DIR/current_verify.sh" || { echo 'PACK_ABORTED: verify failed'; exit 1; }

python3 - "$GK3_STATE" "$SUPER_DIR" "$ZB" "$GK3_OTATOOLS" <<'PY'
import json, os, subprocess, sys, hashlib
state, outdir, zb, OT = sys.argv[1:5]
man = json.load(open(os.path.join(state, 'manifest.json')))
ver = man.get('version', 'dev')
names = ['system', 'system_ext', 'product', 'vendor', 'odm', 'my_product', 'my_stock',
         'my_manifest', 'my_region', 'my_engineering', 'my_heytap', 'my_carrier', 'my_bigball']

def sha256(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for c in iter(lambda: f.read(8 << 20), b''):
            h.update(c)
    return h.hexdigest()

# 账本自证：path 指向的文件必须还是账本记的那份（vendor 退回未打补丁、system 用回基座，
# 这类事故都在这里被挡住，不再靠人记）
for n in names:
    p = man['parts'][n]
    if not os.path.isfile(p['path']):
        raise SystemExit(f'PART_MISSING: {n} -> {p["path"]}')
    if os.path.getsize(p['path']) != p['bytes']:
        raise SystemExit(f'PART_SIZE_MISMATCH: {n}')
    got = sha256(p['path'])
    if got != p['sha256']:
        raise SystemExit(f'PART_SHA_MISMATCH: {n} {got[:16]}… != {p["sha256"][:16]}… (补丁丢了？)')
print('manifest 自证通过：13/13 与账本一致')
lim = 21473689088
F = [man['parts'][n]['path'] for n in names]
total = sum(os.path.getsize(f) for f in F)
print(f'version={ver}  per-slot={total}  total2={total*2}  limit={lim}')
assert total * 2 < lim, 'TOO_BIG'

out = os.path.join(outdir, f'super-{ver}.img')
cmd = [os.path.join(OT, 'lpmake'), '-S', '-F', '-d', '21474836480', '-m', '65536', '-s', '3',
       '--virtual-ab', '-b', '4096', '-g', 'gaokun3_dynamic_partitions_a:21473689088']
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
cmd += ['-o', out]
if os.path.exists(out):
    os.remove(out)
log = open(os.path.join(state, 'logs', 'pack.log'), 'w')
rc = subprocess.call(cmd, stdout=log, stderr=subprocess.STDOUT)
log.close()
if rc != 0:
    print(open(os.path.join(state, 'logs', 'pack.log')).read()[-2000:])
    sys.exit(rc)
alias = os.path.join(outdir, 'super.img')
if os.path.lexists(alias):
    os.remove(alias)
os.symlink(os.path.basename(out), alias)
print('super:', out, os.path.getsize(out))
PY

echo '== 发布'
mkdir -p "$GK3_PUBLISH"
cp -f "$SUPER_DIR/super.img" "$GK3_PUBLISH/super.img"
cd "$GK3_PUBLISH"
sha256sum super.img > super.img.sha256.txt
echo "bytes: $(stat -c%s super.img)" >> super.img.sha256.txt
echo "version: $(python3 -c "import json;print(json.load(open('$GK3_STATE/manifest.json'))['version'])")" >> super.img.sha256.txt
cat super.img.sha256.txt
echo CURRENT_PACK_DONE
