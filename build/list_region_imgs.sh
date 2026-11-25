#!/bin/bash
# 列出可用的 my_region / system 分区镜像（用于选快照源）
set -u
echo "== parts dirs"
ls -d /home/cenmin/coloros-build/*/parts 2>/dev/null
ls -d /home/cenmin/coloros-build/*/src 2>/dev/null
echo "== my_region imgs"
find /home/cenmin/coloros-build /home/cenmin/v50-build -maxdepth 4 -name 'my_region*' -size +1M 2>/dev/null | head -20
echo "== system imgs"
find /home/cenmin/coloros-build -maxdepth 4 -name 'system*.img' 2>/dev/null | head -10
echo "== sizes"
for f in $(find /home/cenmin/coloros-build -maxdepth 4 -name 'my_region*' -size +1M 2>/dev/null | head -20); do
    printf '%s %s %s\n' "$(stat -c%s "$f")" "$(sha256sum "$f" | cut -c1-16)" "$f"
done
