#!/usr/bin/env python3
import os
import subprocess
OT = '/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/lpmake'
P = '/home/cenmin/v5/parts'
SYS = '/home/cenmin/coloros-build/v38/system-v38.erofs'
V = '/home/cenmin/coloros-build/v38/vendor_a_v41.img'
ODM = '/home/cenmin/coloros-build/v38/odm_v38.img'
MYPRODUCT = '/home/cenmin/coloros-build/v39/my_product_a_v39.img'
OUT = '/home/cenmin/coloros-build/super-coloros-v41.simg'
LOG = '/home/cenmin/coloros-build/v41-super.log'
parts = [
    ('system_a', SYS),
    ('system_ext_a', os.path.join(P, 'system_ext_a.img')),
    ('product_a', os.path.join(P, 'product_a.img')),
    ('vendor_a', V),
    ('odm_a', ODM),
    ('my_product_a', MYPRODUCT),
    ('my_stock_a', os.path.join(P, 'my_stock_a.img')),
    ('my_manifest_a', os.path.join(P, 'my_manifest_a.img')),
    ('my_region_a', os.path.join(P, 'my_region_a.img')),
    ('my_engineering_a', os.path.join(P, 'my_engineering_a.img')),
    ('my_heytap_a', os.path.join(P, 'my_heytap_a.img')),
    ('my_carrier_a', os.path.join(P, 'my_carrier_a.img')),
    ('my_bigball_a', os.path.join(P, 'my_bigball_a.img')),
]
for _, path in parts:
    if not os.path.isfile(path):
        raise SystemExit(f'missing partition: {path}')
cmd = [OT, '-S', '-F', '-d', '12884901888', '-m', '65536', '-s', '3',
       '--virtual-ab', '-b', '4096',
       '-g', 'gaokun3_dynamic_partitions_a:12683575296']
for name, path in parts:
    cmd += ['-p', f'{name}:none:{os.path.getsize(path)}:gaokun3_dynamic_partitions_a']
for name, path in parts:
    cmd += ['-i', f'{name}={path}']
cmd += ['-o', OUT]
if os.path.exists(OUT):
    os.remove(OUT)
with open(LOG, 'w') as f:
    subprocess.run(cmd, check=True, stdout=f, stderr=subprocess.STDOUT)
print(OUT)
print(os.path.getsize(OUT))
subprocess.run(['sha256sum', OUT], check=True)
print('SUPER_V41_BUILT')