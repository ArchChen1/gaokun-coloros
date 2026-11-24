#!/usr/bin/env bash
# 抓取构建输入：11 个分区文件 + 两棵解包树（system / odm）。
#
# 清单分两份：
#   inputs/targets.txt   <sha256> <bytes> <target>      完整文件的目标 sha
#   inputs/slices.txt    <sha256> <bytes> <asset> <target>   资产分片（GitHub Release 单资产 ≤2 GB）
#
# 抓取顺序：分片下载 → 校验每个分片 → 拼成完整文件 → 校验目标 sha → 树自动解包。
# 已有且 sha 匹配的目标直接跳过，所以重复执行是幂等的。
#
#   sudo -E bash build/fetch.sh                                  # 默认从本仓库的 Release 拉
#   GK3_INPUT_BASE_URL=https://mirror/base sudo -E bash build/fetch.sh
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/env.sh"

TARGETS="$REPO/inputs/targets.txt"
SLICES="$REPO/inputs/slices.txt"
BASE="${GK3_INPUT_BASE_URL:-https://github.com/${GK3_REPO_SLUG:-ArchChen1/gaokun-coloros}/releases/download/inputs-v1}"
BASE="${BASE%/}"
PART_DIR="$GK3_WORKDIR/.parts"

mkdir -p "$GK3_INPUTS" "$GK3_SRC" "$GK3_TREES" "$PART_DIR"

sha_of() { sha256sum "$1" | cut -d' ' -f1; }

is_tree() { case "$1" in trees/*) return 0 ;; *) return 1 ;; esac; }

dst_of() {  # 目标 → 落地路径 / 树目录
  case "$1" in
    trees/*) echo "$GK3_TREES/${1#trees/}" ;;
    src/*)   echo "$GK3_SRC/${1#src/}" ;;
    *)       echo "$GK3_INPUTS/$1" ;;
  esac
}

marker_of() { echo "$GK3_TREES/.gk3-tree-$(printf '%s' "$1" | tr '/' '_').sha"; }

# 已完成？
done_already() {  # <target> <sha>
  if is_tree "$1"; then
    local d m; d=$(dst_of "$1"); m=$(marker_of "$1")
    [ -d "$d" ] && [ -f "$m" ] && [ "$(cat "$m")" = "$2" ]
  else
    local p; p=$(dst_of "$1")
    [ -s "$p" ] && [ "$(sha_of "$p")" = "$2" ]
  fi
}

fetch_part() {  # <asset> <sha> → $PART_DIR/<asset>
  local asset=$1 want=$2 dst="$PART_DIR/$1"
  mkdir -p "$PART_DIR"
  if [ -s "$dst" ] && [ "$(sha_of "$dst")" = "$want" ]; then return 0; fi
  echo "    <- $asset"
  curl -fL --retry 3 --retry-delay 2 -C - -o "$dst.part" "$BASE/$asset" || { rm -f "$dst.part"; return 1; }
  local got; got=$(sha_of "$dst.part")
  [ "$got" = "$want" ] || { echo "    FAIL 分片 sha 不符 $asset（$got）"; rm -f "$dst.part"; return 1; }
  mv -f "$dst.part" "$dst"
}

[ -f "$TARGETS" ] && [ -f "$SLICES" ] || {
  echo "缺 inputs/targets.txt 或 inputs/slices.txt" >&2; exit 1
}

# 解包树要恢复 SELinux 标签（security.selinux），非 root 会静默丢标签 → 镜像起来后系统分区读不到
if [ "$(id -u)" -ne 0 ]; then
  need=0
  while read -r tsha tbytes tname; do
    case "${tsha:-}" in ''|'#'*) continue ;; esac
    is_tree "$tname" && ! done_already "$tname" "$tsha" && need=1
  done < "$TARGETS"
  [ "$need" -eq 0 ] || { echo '需要 root：解包树要写 security.selinux 标签 → sudo -E make fetch' >&2; exit 1; }
fi

ok=0; skip=0; fail=0
while read -r tsha tbytes target; do
  case "${tsha:-}" in ''|'#'*) continue ;; esac
  if done_already "$target" "$tsha"; then echo "  已有 $target"; skip=$((skip+1)); continue; fi

  echo "== $target（$((tbytes/1024/1024)) MiB）"
  mapfile -t parts < <(awk -v t="$target" '$4==t {print $3}' "$SLICES")
  [ "${#parts[@]}" -gt 0 ] || { echo "  FAIL 清单里没有 $target 的分片"; fail=$((fail+1)); continue; }

  bad=0
  for p in "${parts[@]}"; do
    want=$(awk -v a="$p" '$3==a {print $1}' "$SLICES")
    fetch_part "$p" "$want" || { bad=1; break; }
  done
  [ "$bad" -eq 0 ] || { echo "  FAIL 下载失败 $target"; fail=$((fail+1)); continue; }

  if is_tree "$target"; then
    asm="$PART_DIR/tree-$(printf '%s' "${target#trees/}").tar.zst"
  else
    asm="$(dst_of "$target").assembling"
  fi
  mkdir -p "$(dirname "$asm")"
  : > "$asm"
  for p in "${parts[@]}"; do cat "$PART_DIR/$p" >> "$asm"; done

  got=$(sha_of "$asm")
  if [ "$got" != "$tsha" ]; then
    echo "  FAIL 拼装后 sha 不符 $target（$got）"; rm -f "$asm"; fail=$((fail+1)); continue
  fi

  if is_tree "$target"; then
    d=$(dst_of "$target")
    echo "  解包树 → $d"
    rm -rf "$d"
    zstd -dc "$asm" | tar --xattrs --xattrs-include='*' -xf - -C "$GK3_TREES" \
      || { echo "  FAIL 解包失败 $target"; fail=$((fail+1)); continue; }
    printf '%s' "$tsha" > "$(marker_of "$target")"
    rm -f "$asm"
  else
    mv -f "$asm" "$(dst_of "$target")"
  fi
  rm -f "${parts[@]/#/$PART_DIR/}"
  ok=$((ok+1))
done < "$TARGETS"

echo "完成：下载 $ok，跳过 $skip，失败 $fail"
[ "$fail" -eq 0 ] || exit 1
echo FETCH_OK
