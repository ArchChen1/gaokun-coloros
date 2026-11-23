#!/usr/bin/env bash
set -euo pipefail
O=/home/cenmin/coloros-build/v50
V51=/home/cenmin/coloros-build/v51
mkdir -p "$V51"
V=$V51/vendor_a_v51.img
cp --reflink=auto "$O/vendor_a_v50.img" "$V"
mkdir -p /mnt/vv; umount /mnt/vv 2>/dev/null || true
mount -t ext4 -o loop,rw "$V" /mnt/vv
echo "driver before: $(sha256sum /mnt/vv/lib64/hw/vulkan.freedreno.so)"
python3 - <<'PY'
import os
path='/mnt/vv/lib64/hw/vulkan.freedreno.so'
offs=(0xa5d30,0xa5d48)
with open(path,'r+b') as f:
    for o in offs:
        f.seek(o); b=f.read(1)
        if b != b'\x01':
            raise SystemExit(f'unexpected byte at {o}: {b!r}')
        f.seek(o); f.write(b'\x02')
print('patched driver bytes')
PY
echo "driver after: $(sha256sum /mnt/vv/lib64/hw/vulkan.freedreno.so)"
python3 - <<'PY'
path='/mnt/vv/build.prop'
data=open(path,'rb').read()
old=b'debug.hwui.renderer=skiagl'
new=b'debug.hwui.renderer=skiavk'
if old not in data:
    raise SystemExit('renderer line not found')
data=data.replace(old,new,1)
open(path,'wb').write(data)
print('renderer set to skiavk')
PY
grep -a 'debug.hwui.renderer' /mnt/vv/build.prop
umount /mnt/vv
e2fsck -fn "$V" 2>&1 | tail -2
dumpe2fs -h "$V" 2>/dev/null | grep -E 'Block count|Free blocks'
stat -c%s "$V"
echo V51_VENDOR_DONE
