#!/usr/bin/env python3
"""静态求 /odm/bin/hw/vendor.oplus.hardware.charger-V12-service 的动态库依赖闭包，
判定哪些依赖只能从 system 侧拿到（vendor 命名空间看不见，必须拷进 odm/lib64）。"""
import os, subprocess, sys

ODM = '/home/cenmin/v50-build/odm'
SYSD = '/home/cenmin/v50-build/system/system'
P = '/home/cenmin/coloros-build'
SRC = '/home/cenmin/coloros-build/v49/src'

# 每个“可见域”的 lib 目录（vendor 进程实际能看到的只有前两个域）
DOMAINS = {
    'odm': [f'{ODM}/lib64'],
    'vendor': ['/mnt/cv/lib64'],
    'system': [f'{SYSD}/lib64'],
    'system_ext': ['/mnt/se/lib64', '/mnt/se/lib'],
    'my_product': [f'{P}/mp/lib64'],
    'my_stock': [f'{P}/ms/lib64'],
    'product': [f'{P}/pd/lib64'],
}
VISIBLE = ('odm', 'vendor')

idx = {}
for dom, dirs in DOMAINS.items():
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for f in os.listdir(d):
            if f.endswith('.so') and os.path.isfile(os.path.join(d, f)):
                idx.setdefault(f, []).append((dom, os.path.join(d, f)))

def needed(path):
    try:
        out = subprocess.run(['readelf', '-d', path], capture_output=True, text=True).stdout
    except Exception:
        return []
    libs = []
    for line in out.splitlines():
        if 'NEEDED' in line and '[' in line:
            libs.append(line.split('[')[1].split(']')[0])
    return libs

root = f'{ODM}/bin/hw/vendor.oplus.hardware.charger-V12-service'
if not os.path.exists(root):
    sys.exit(f'missing root: {root}')

seen, queue, need_copy = {}, [(os.path.basename(root), root, 'root')], []
while queue:
    name, path, origin = queue.pop()
    if name in seen:
        continue
    seen[name] = origin
    for lib in needed(path):
        if lib in seen:
            continue
        locs = idx.get(lib, [])
        vis = [l for l in locs if l[0] in VISIBLE]
        if vis:
            queue.append((lib, vis[0][1], vis[0][0]))
        elif locs:
            queue.append((lib, locs[0][1], locs[0][0]))
            need_copy.append(lib)
        else:
            seen[lib] = 'MISSING-ANYWHERE'
            print(f'  !! {lib}: 整个树里都找不到（{name} 需要）')

print('\n== 只能从 system 侧拿到、必须进 odm/lib64 的库')
for n in sorted(set(need_copy)):
    print(' ', n, '->', idx[n][0][1])

print(f'\n== 闭包统计: {len(seen)} 个节点, 需补 {len(set(need_copy))} 个')
