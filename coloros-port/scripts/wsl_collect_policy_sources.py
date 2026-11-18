#!/usr/bin/env python3
import os, shutil, subprocess
from pathlib import Path

src = Path('/mnt/e/gaokun-coloros/coloros-port/work/opd2513')
base = Path('/home/cenmin/coloros-build/policy-src')
mounts = {
    'system': src / 'system.img',
    'system_ext': src / 'system_ext.img',
    'product': src / 'product.img',
    'vendor': src / 'vendor.img',
    'odm': src / 'odm.img',
}
selinux_sources = {
    'system': Path('/mnt/policy-system/system/etc/selinux'),
    'system_ext': Path('/mnt/policy-system_ext/etc/selinux'),
    'product': Path('/mnt/policy-product/etc/selinux'),
    'vendor': Path('/mnt/policy-vendor/etc/selinux'),
    'odm': Path('/mnt/policy-odm/etc/selinux'),
}
for name, image in mounts.items():
    target = Path('/mnt/policy-' + name)
    target.mkdir(parents=True, exist_ok=True)
    subprocess.run(['umount', str(target)], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(['mount', '-t', 'erofs', '-o', 'loop,ro', str(image), str(target)], check=True)
try:
    for name, source in selinux_sources.items():
        dest = base / name
        dest.mkdir(parents=True, exist_ok=True)
        if source.is_dir():
            for item in source.iterdir():
                if item.is_dir():
                    if (dest / item.name).exists():
                        shutil.rmtree(dest / item.name)
                    shutil.copytree(item, dest / item.name)
                else:
                    shutil.copy2(item, dest / item.name)
            print(name + ': copied from ' + str(source))
        else:
            print(name + ': source missing ' + str(source))
finally:
    for name in reversed(list(mounts)):
        subprocess.run(['umount', '/mnt/policy-' + name], check=False)

for name in ['system', 'system_ext', 'product', 'vendor', 'odm']:
    dest = base / name
    print('==== ' + name)
    for path in sorted(dest.rglob('*')):
        if path.is_file():
            print(str(path.relative_to(dest)) + ' ' + str(path.stat().st_size))