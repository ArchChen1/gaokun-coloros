#!/bin/bash
# 找可用的 liblp 工具（lpmake/lpadd/lpdump/lpremove/lpflash）与 python 实现
set -u
echo "== which"
for t in lpmake lpadd lpdump lpremove lpflash lpresize lpmerge lpunpack; do
    printf '%-10s %s\n' "$t" "$(command -v $t 2>/dev/null || echo -)"
done
echo "== find in toolchain/build dirs"
find /home/cenmin/toolchain /home/cenmin/coloros-build -maxdepth 5 -type f \( -name 'lpmake' -o -name 'lpadd' -o -name 'lpdump' -o -name 'lpremove' \) 2>/dev/null | head -10
echo "== find python liblp"
find /home/cenmin -maxdepth 6 -type f \( -name '*liblp*' -o -name '*lpunpack*' -o -name 'lp*.py' \) 2>/dev/null | head -20
echo "== stock tools on host"
ls -l /usr/bin/lp* 2>/dev/null | head
