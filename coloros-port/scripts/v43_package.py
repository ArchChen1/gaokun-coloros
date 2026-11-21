#!/usr/bin/env python3
import os
import shutil
import subprocess

CB = '/home/cenmin/coloros-build'
REL = os.path.join(CB, 'release-coloros-v43')
os.makedirs(REL, exist_ok=True)
shutil.copy2(os.path.join(CB, 'release-coloros-v32r4', 'boot.img'),
             os.path.join(REL, 'boot.img'))
out = os.path.join(REL, 'super.img.zst')
subprocess.run(['zstd', '-T0', '-12', '-f', os.path.join(CB, 'super-coloros-v43.simg'),
                '-o', out], check=True)
subprocess.run(['zstd', '-t', out], check=True)
lines = []
for name in ['boot.img', 'super.img.zst']:
    h = subprocess.check_output(['sha256sum', os.path.join(REL, name)], text=True).split()[0]
    lines.append(h + '  ' + name)
with open(os.path.join(REL, 'install-artifacts.sha256'), 'w') as f:
    f.write('\n'.join(lines) + '\n')
components = [
    ('system-v43.erofs', os.path.join(CB, 'v43', 'system-v43.erofs')),
    ('system_ext_v43.erofs', os.path.join(CB, 'v43', 'system_ext_v43.erofs')),
    ('product_v43.erofs', os.path.join(CB, 'v43', 'product_v43.erofs')),
    ('vendor_a_v43.img', os.path.join(CB, 'v43', 'vendor_a_v43.img')),
    ('odm_v43.erofs', os.path.join(CB, 'v43', 'odm_v43.erofs')),
    ('my_product_a_v43.erofs', os.path.join(CB, 'v43', 'my_product_a_v43.erofs')),
    ('my_stock_a_v43.erofs', os.path.join(CB, 'v43', 'my_stock_a_v43.erofs')),
    ('super-coloros-v43.simg', os.path.join(CB, 'super-coloros-v43.simg')),
    ('boot.img', os.path.join(REL, 'boot.img')),
]
with open(os.path.join(REL, 'components.sha256'), 'w') as f:
    for name, path in components:
        h = subprocess.check_output(['sha256sum', path], text=True).split()[0]
        f.write('%s  %s\n' % (h, name))
print('PACKED', REL)
subprocess.run(['ls', '-lh', REL], check=True)
print(open(os.path.join(REL, 'install-artifacts.sha256')).read())