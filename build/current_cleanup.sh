#!/usr/bin/env bash
# 清理构建中间物：只删 STATE 下的 release/zb 与 WORKDIR/tmp，路径来自 env.sh 并做范围校验。
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/env.sh"

guard() {
  case "$1" in
    "$GK3_STATE"/*|"$GK3_WORKDIR"/tmp/*) ;;
    *) echo "REFUSE: 越界路径 $1"; exit 1 ;;
  esac
  [ -n "$1" ] || { echo 'REFUSE: 空路径'; exit 1; }
  [ "$1" != '/' ] || { echo 'REFUSE: 根目录'; exit 1; }
}

for t in "$GK3_STATE/release" "$GK3_STATE/zb" "$GK3_WORKDIR/tmp"; do
  guard "$t"
  [ -e "$t" ] && { rm -rf -- "$t"; echo "removed $t"; }
done

df -h "$GK3_WORKDIR" 2>/dev/null | tail -1
echo CLEANUP_DONE
