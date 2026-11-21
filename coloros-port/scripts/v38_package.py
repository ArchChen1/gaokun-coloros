#!/usr/bin/env python3
import os
import shutil
import subprocess
CB = '/home/cenmin/coloros-build'
REL = os.path.join(CB, 'release-coloros-v38')
os.makedirs(REL, exist_ok=True)
shutil.copy2(os.path.join(CB, 'release-coloros-v32r4', 'boot.img'), os.path.join(REL, 'boot.img'))
out = os.path.join(REL, 'super.img.zst')
subprocess.run(['zstd', '-T0', '-12', '-f', os.path.join(CB, 'super-coloros-v38.simg'), '-o', out], check=True)
subprocess.run(['zstd', '-t', out], check=True)
lines = []
for name in ['boot.img', 'super.img.zst']:
    h = subprocess.check_output(['sha256sum', os.path.join(REL, name)], text=True).split()[0]
    lines.append(h + '  ' + name)
with open(os.path.join(REL, 'install-artifacts.sha256'), 'w') as f:
    f.write('\n'.join(lines) + '\n')
print('PACKED', REL)
subprocess.run(['ls', '-lh', REL], check=True)
print(open(os.path.join(REL, 'install-artifacts.sha256')).read())