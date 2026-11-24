#!/usr/bin/env bash
# 把构建输入打成分片，供 GitHub Release 托管，并生成 inputs/{targets,slices}.txt。
#
#   sudo -E bash build/export_inputs.sh            # 输出到 $HOME/gk3-slices
#   GK3_SLICES_OUT=/path sudo -E bash build/export_inputs.sh
#
# 为什么要分片：GitHub Release 单个资产上限 2 GB，而 my_stock.erofs 就有 4 GB。
# 为什么要打包树：system/ 与 odm/ 是解包后的文件树（含 SELinux 标签），不打包会把几万个文件塞进 git。
#
# 产物：
#   $GK3_SLICES_OUT/<asset>            资产文件（.partNNN 结尾）
#   inputs/slices.txt                  <part_sha256> <part_bytes> <asset> <target>
#   inputs/targets.txt                 <sha256> <bytes> <target>  （target 为完整文件的 sha）
#
# 树打成 tar.zst 时固定 mtime / 属主 / 排序，保证同样的树打包得到同样的 tar（可复现）。
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/env.sh"

OUT=${GK3_SLICES_OUT:-$HOME/gk3-slices}
SLICE=${GK3_SLICE_BYTES:-1900000000}   # < 2 GB，留余量
MAN="$REPO/inputs/manifest.txt"

[ "$(id -u)" -eq 0 ] || { echo '需要 root（读树的 SELinux 标签）：sudo -E bash build/export_inputs.sh' >&2; exit 1; }
[ -d "$GK3_TREES" ] || { echo "缺解包树目录 $GK3_TREES" >&2; exit 1; }

mkdir -p "$OUT"
SL="$OUT/slices.txt"
TG="$OUT/targets.txt"
: > "$SL"
: > "$TG"

split_file() {  # <源文件> <资产前缀> <target>
  local src=$1 prefix=$2 target=$3 p
  rm -f "$prefix".part*
  split -b "$SLICE" -d -a 3 "$src" "$prefix.part"
  for p in "$prefix".part*; do
    printf '%s %s %s %s\n' "$(sha256sum "$p" | cut -d' ' -f1)" "$(stat -c%s "$p")" "$(basename "$p")" "$target" >> "$SL"
  done
}

echo "== 1. 原始输入（$GK3_INPUTS）"
while read -r sha bytes name url; do
  case "${sha:-}" in ''|'#'*) continue ;; esac
  src="$GK3_INPUTS/$name"
  case "$name" in src/*) src="$GK3_SRC/${name#src/}" ;; esac
  [ -s "$src" ] || { echo "缺输入 $src" >&2; exit 1; }
  base=$(printf '%s' "$name" | tr '/' '_')
  split_file "$src" "$OUT/$base" "$name"
  printf '%s %s %s\n' "$sha" "$bytes" "$name" >> "$TG"
  echo "  $name → $(ls "$OUT/$base".part* | wc -l) 片"
done < "$MAN"

echo '== 2. 解包树（tar.zst）'
for t in system odm; do
  [ -d "$GK3_TREES/$t" ] || { echo "缺树 $GK3_TREES/$t" >&2; exit 1; }
  art="$OUT/trees-$t.tar.zst"
  rm -f "$art"
  tar --xattrs --xattrs-include='*' --sort=name --mtime='2026-01-01 00:00:00Z' \
      --owner=0 --group=0 --numeric-owner -C "$GK3_TREES" -cf - "$t" \
    | zstd -T0 -6 -q -o "$art"
  printf '%s %s trees/%s\n' "$(sha256sum "$art" | cut -d' ' -f1)" "$(stat -c%s "$art")" "$t" >> "$TG"
  split_file "$art" "$art" "trees/$t"
  echo "  trees/$t → raw $(du -sb "$GK3_TREES/$t" | cut -f1) / zst $(stat -c%s "$art") / $(ls "$art".part* | wc -l) 片"
  rm -f "$art"   # 只留分片，省地方
done

echo '== 3. 写清单'
cp -f "$SL" "$REPO/inputs/slices.txt"
cp -f "$TG" "$REPO/inputs/targets.txt"
echo '  目标：'
awk '{printf "    %-28s %12d  %s\n", $3, $2, substr($1,1,12)}' "$TG"
echo "  分片：$(wc -l < "$SL") 个，合计 $(awk '{s+=$2} END{printf "%.2f GB", s/1e9}' "$SL")"
echo "  输出目录：$OUT"
echo EXPORT_OK
