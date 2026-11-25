#!/usr/bin/env bash
# 把 vendor.img 里的 v4l2 C2 HAL 打开：补 interface aidl 的 lazy-start 声明、去掉 disabled。
# 用法：sudo bash build/patch_vendor_c2_hal.sh <vendor.img>
#
# 背景：/vendor/etc/init/android.hardware.media.c2-service-v4l2.rc 原本是 disabled 且没有
# interface aidl，init 从不拉起这个 HAL，于是 binder 上只有 IComponentStore/software，
# 硬件编解码组件一个都不注册（Codec Info 里全 false）。详见 docs/HW-CODEC2.md。
# 幂等：已经打过就只提示。改完镜像字节数不变，可以按 super extent 原位写回。
set -euo pipefail

IMG=${1:?用法: patch_vendor_c2_hal.sh <vendor.img>}
[ -s "$IMG" ] || { echo "找不到镜像: $IMG"; exit 1; }

MNT=$(mktemp -d)
trap 'umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT

SIZE_BEFORE=$(stat -c%s "$IMG")
mount -t ext4 -o loop,rw "$IMG" "$MNT"

RC="$MNT/etc/init/android.hardware.media.c2-service-v4l2.rc"
if [ ! -f "$RC" ]; then
    echo "镜像里没有 $RC（这版 vendor 不是这套 C2 HAL）"
    exit 1
fi

python3 - "$RC" <<'PY'
import sys

p = sys.argv[1]
d = open(p).read()
if 'IComponentStore/default' in d:
    print('已打过补丁，跳过')
    sys.exit(0)

lines = d.splitlines()
idx = next((i for i, l in enumerate(lines)
            if l.startswith('service android-hardware-media-c2-v4l2-hal')), None)
if idx is None:
    raise SystemExit('找不到 service 声明，rc 结构和预期不符')

# disabled 的服务既不会随 class 起，也没有 lazy-start 可依赖
j = idx + 1
while j < len(lines) and (lines[j].startswith(' ') or lines[j].strip() == ''):
    if lines[j].strip() == 'disabled':
        lines.pop(j)
        continue
    j += 1

lines.insert(idx + 1, '    interface aidl android.hardware.media.c2.IComponentStore/default')
open(p, 'w').write('\n'.join(lines).rstrip('\n') + '\n')
print('rc: 去掉 disabled + 补 interface aidl')
PY

umount "$MNT"
e2fsck -fn "$IMG" >/dev/null 2>&1 && echo "fsck clean" || echo "fsck 报错（仅提示）"
echo "size: $SIZE_BEFORE -> $(stat -c%s "$IMG")"
sha256sum "$IMG"
