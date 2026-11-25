#!/bin/bash
# 把 v50-build 的 system 树收敛到发布状态（幂等）：
#   · build.prop 去掉 ro.virtual_ab.*
#   · snapuserd.rc 去掉 -ublk、gk3clean、gk3run 三段
#   · 删掉 gk3-logdump.rc / gk3-logdump.sh（/metadata 转储钩子）
# 全部内容见 docs/OTA-LEGACY-AB.md「发布清理」。调试用副本在
# vendor/gaokun-android/device/huawei/gaokun3/debug/。
#
# 用法：
#   wsl -u root -d Ubuntu-24.04 -- bash /mnt/e/gk3-coloros/build/cleanup_system_release.sh
set -eu
TREE=${TREE:-/home/cenmin/v50-build/system/system}
[ -d "$TREE/bin" ] || { echo "树不存在：$TREE"; exit 1; }

# 1) build.prop
sed -i '/^ro\.virtual_ab\.ublk\.enabled=/d; /^ro\.virtual_ab\.userspace\.snapshots\.enabled=/d' "$TREE/build.prop"

# 2) snapuserd.rc
python3 - "$TREE/etc/init/snapuserd.rc" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().splitlines(True)
out, i = [], 0
while i < len(lines):
    l = lines[i]
    if l.startswith('service snapuserd /system/bin/snapuserd -ublk'):
        out.append('service snapuserd /system/bin/snapuserd\n'); i += 1; continue
    if l.startswith('service gk3clean') or l.startswith('service gk3run') or l.strip() == 'on boot':
        i += 1
        while i < len(lines) and lines[i].strip() != '':
            i += 1
        continue
    out.append(l); i += 1
while out and out[-1].strip() == '':
    out.pop()
open(p, 'w').write(''.join(out) + '\n')
PY

# 3) 转储钩子
rm -f "$TREE/etc/init/gk3-logdump.rc" "$TREE/etc/gk3-logdump.sh"

echo "== 清理结果"
if grep -q 'ro\.virtual_ab' "$TREE/build.prop"; then echo "   !! build.prop 仍有 ro.virtual_ab"; exit 5; fi
if grep -q 'gk3run\|gk3clean\|snapuserd -ublk' "$TREE/etc/init/snapuserd.rc"; then
    echo "   !! snapuserd.rc 仍有残留"; grep -n 'gk3\|ublk' "$TREE/etc/init/snapuserd.rc"; exit 5; fi
[ -e "$TREE/etc/init/gk3-logdump.rc" ] && { echo "   !! 转储钩子还在"; exit 5; }
echo "   通过（build.prop / snapuserd.rc / 钩子均已收敛）"
nl -ba "$TREE/etc/init/snapuserd.rc" | tail -4
