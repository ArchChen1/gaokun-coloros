#!/usr/bin/env bash
# 按 config/kernel-patch-manifest.txt 把补丁打进一棵内核树。
#
# 前置：树已经是 mainline v7.2.9 + buildbot 构建层（见 docs/KERNEL-BUILD.md）。
# 用法：
#   GAOKUN_SRC=/path/to/gaokun-android bash scripts/kernel-apply-coloros.sh /path/to/linux [--check]
#   --check  只演算，不改树
#
# 幂等：已打上的补丁用反向 --check 判定后跳过，可反复跑。
#
# ⚠️ --check 在【已经打满】的树上会误报 FAIL：叠加补丁里靠前的那个被后面的补丁改写过上下文，
#    反向 --check 对不上，正向 --check 也报不上，但树其实是对的。
#    要精确核对请用 gaokun-src 自己的 scripts/kernel-apply-patches.sh <tree> --verify
#    （它在干净 worktree 上重放整条链，再逐文件比 md5）。
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
MANIFEST="$ROOT/config/kernel-patch-manifest.txt"
GAOKUN_SRC=${GAOKUN_SRC:-$HOME/gaokun-src}
TREE=${1:-}
MODE=${2:-apply}

[ -n "$TREE" ] && [ -f "$TREE/Makefile" ] || { echo "用法: $0 <内核树路径> [--check]" >&2; exit 2; }
[ -d "$GAOKUN_SRC/patches/kernel" ] || { echo "找不到 $GAOKUN_SRC/patches/kernel（用 GAOKUN_SRC 指过去）" >&2; exit 2; }

# 展开清单：先全部加入，再按 - 行剔除
ALL=$(mktemp) KEEP=$(mktemp)
grep -E '^\+ ' "$MANIFEST" | sed 's/^+ //' | while read -r g; do
  (cd "$GAOKUN_SRC/patches/kernel" && ls -1d $g 2>/dev/null)
done >> "$ALL"
grep -E '^- ' "$MANIFEST" | sed 's/^- //' | while read -r g; do
  (cd "$GAOKUN_SRC/patches/kernel" && ls -1d $g 2>/dev/null)
done > "$KEEP"

LIST=$(mktemp)
grep -vxF -f "$KEEP" "$ALL" > "$LIST" || true
echo "补丁总数: $(wc -l < "$LIST")  排除: $(wc -l < "$KEEP")"

rc=0
while read -r rel; do
  p="$GAOKUN_SRC/patches/kernel/$rel"
  if git -C "$TREE" apply --reverse --check "$p" >/dev/null 2>&1; then
    echo "SKIP $rel"; continue
  fi
  if [ "$MODE" = "--check" ]; then
    if git -C "$TREE" apply --check "$p" >/dev/null 2>&1; then echo "OK   $rel"; else echo "FAIL $rel"; rc=1; fi
  else
    if git -C "$TREE" am "$p" >/tmp/kernel-apply.log 2>&1; then
      echo "OK   $rel"
    else
      echo "FAIL $rel"; tail -6 /tmp/kernel-apply.log; git -C "$TREE" am --abort >/dev/null 2>&1; rc=1
    fi
  fi
done < "$LIST"
exit $rc
