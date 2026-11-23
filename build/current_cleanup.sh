#!/usr/bin/env bash
# 清理旧的构建产物，只删本脚本里逐条硬编码的绝对路径；不做变量拼接。
set -uo pipefail
guard() {
  p="$1"
  case "$p" in
    /home/cenmin/coloros-build/*) ;;
    *) echo "REFUSE: 不在构建根下: $p"; exit 1 ;;
  esac
  [ -n "$p" ] || { echo 'REFUSE: 空路径'; exit 1; }
  [ "$p" != '/' ] || { echo 'REFUSE: 根目录'; exit 1; }
}

targets=(
  /home/cenmin/coloros-build/v36
  /home/cenmin/coloros-build/v37
  /home/cenmin/coloros-build/v38
  /home/cenmin/coloros-build/v39
  /home/cenmin/coloros-build/v43
  /home/cenmin/coloros-build/v53
  /home/cenmin/coloros-build/v52/zb
  /home/cenmin/coloros-build/v52/u52
  /home/cenmin/coloros-build/current/release
)
for t in "${targets[@]}"; do
  guard "$t"
  [ -e "$t" ] && { rm -rf -- "$t"; echo "removed $t"; }
done

files=(
  /home/cenmin/coloros-build/v52/super-coloros-v52.img
  /home/cenmin/coloros-build/v52/system_a_v52.erofs
  /home/cenmin/coloros-build/v52/system_a_v52b.erofs
  /home/cenmin/coloros-build/v52/system_a_v52c.erofs
  /home/cenmin/coloros-build/v52/system_a_v52d.erofs
  /home/cenmin/coloros-build/v52/system_a_v52e.erofs
  /home/cenmin/coloros-build/v52/odm_a_v52.erofs
  /home/cenmin/coloros-build/v52/odm_a_v52b.erofs
  /home/cenmin/coloros-build/v52/my_product_a_v52.erofs
  /home/cenmin/coloros-build/v52/system_ext_a_v52.erofs
  /home/cenmin/coloros-build/v50/super-coloros-v50.img
  /home/cenmin/coloros-build/v51/super-coloros-v51.img
)
for f in "${files[@]}"; do
  guard "$f"
  [ -f "$f" ] && { rm -f -- "$f"; echo "removed $f"; }
done

df -h / | tail -1
du -sh /home/cenmin/coloros-build/v52 /home/cenmin/coloros-build/v49 /home/cenmin/coloros-build/current 2>/dev/null
echo CLEANUP_DONE
