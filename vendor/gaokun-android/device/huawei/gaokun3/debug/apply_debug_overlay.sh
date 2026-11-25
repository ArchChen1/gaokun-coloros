#!/bin/bash
# 把 debug/ 里的调试覆盖层叠回 v50-build 树（发布镜像不带这些，见 README.md）。
set -eu
D=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TREE=${TREE:-/home/cenmin/v50-build/system/system}
[ -d "$TREE/bin" ] || { echo "树不存在：$TREE"; exit 1; }

cp -f "$D/gk3-logdump.rc"  "$TREE/etc/init/gk3-logdump.rc"
cp -f "$D/gk3-logdump.sh"  "$TREE/etc/gk3-logdump.sh"
chmod 644 "$TREE/etc/init/gk3-logdump.rc"
chmod 755 "$TREE/etc/gk3-logdump.sh"

if grep -q 'service gk3run' "$TREE/etc/init/snapuserd.rc"; then
    echo "snapuserd.rc 已有 gk3run，跳过追加"
else
    echo >> "$TREE/etc/init/snapuserd.rc"
    sed '/^#/d' "$D/gk3run-service.rc" >> "$TREE/etc/init/snapuserd.rc"
    echo "已追加 gk3run / gk3clean 到 snapuserd.rc"
fi

echo "== 叠加后："
ls -l "$TREE/etc/init/gk3-logdump.rc" "$TREE/etc/gk3-logdump.sh"
nl -ba "$TREE/etc/init/snapuserd.rc" | tail -22
