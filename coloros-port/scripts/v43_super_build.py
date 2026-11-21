#!/usr/bin/env python3
import os
import subprocess

OT = '/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/lpmake'
P = '/home/cenmin/v5/parts'
B = '/home/cenmin/coloros-build/v43'
OUT = '/home/cenmin/coloros-build/super-coloros-v43.simg'
LOG = '/home/cenmin/coloros-build/v43-super.log'
parts = [
    ('system_a', os.path.join(B, 'system-v43.erofs')),
    ('system_ext_a', os.path.join(B, 'system_ext_v43.erofs')),
    ('product_a', os.path.join(B, 'product_v43.erofs')),
    ('vendor_a', os.path.join(B, 'vendor_a_v43.img')),
    ('odm_a', os.path.join(B, 'odm_v43.erofs')),
    ('my_product_a', os.path.join(B, 'my_product_a_v43.erofs')),
    ('my_stock_a', os.path.join(B, 'my_stock_a_v43.erofs')),
    ('my_manifest_a', os.path.join(P, 'my_manifest_a.img')),
    ('my_region_a', os.path.join(P, 'my_region_a.img')),
    ('my_engineering_a', os.path.join(P, 'my_engineering_a.img')),
    ('my_heytap_a', os.path.join(P, 'my_heytap_a.img')),
    ('my_carrier_a', os.path.join(P, 'my_carrier_a.img')),
    ('my_bigball_a', os.path.join(P, 'my_bigball_a.img')),
]
for _, path in parts:
    if not os.path.isfile(path):
        raise SystemExit('missing partition: ' + path)
cmd = [OT, '-S', '-F', '-d', '12884901888', '-m', '65536', '-s', '3',
       '--virtual-ab', '-b', '4096',
       '-g', 'gaokun3_dynamic_partitions_a:12683575296']
for name, path in parts:
    cmd += ['-p', '%s:none:%d:gaokun3_dynamic_partitions_a' % (name, os.path.getsize(path))]
for name, path in parts:
    cmd += ['-i', '%s=%s' % (name, path)]
cmd += ['-o', OUT]
if os.path.exists(OUT):
    os.remove(OUT)
with open(LOG, 'w') as f:
    subprocess.run(cmd, check=True, stdout=f, stderr=subprocess.STDOUT)
print(OUT)
print(os.path.getsize(OUT))
subprocess.run(['sha256sum', OUT], check=True)
print('SUPER_V43_BUILT')