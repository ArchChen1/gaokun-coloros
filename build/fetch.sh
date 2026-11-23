#!/usr/bin/env bash
# 抓取构建输入（vendor_base.img、my_product.erofs、my_stock.erofs、src/*）。
# 清单：inputs/manifest.txt，格式 “sha256  bytes  name  url(可选)”。
# 若本机已有同名文件且 sha 匹配，则跳过下载。
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/env.sh"

MAN="$REPO/inputs/manifest.txt"
[ -f "$MAN" ] || { echo "缺清单 $MAN"; exit 1; }
mkdir -p "$GK3_INPUTS" "$GK3_SRC"
: "${GK3_INPUT_BASE_URL:=}"

ok=0; skip=0; fail=0
while read -r sha bytes name url; do
  case "${sha:-}" in ''|'#'*) continue ;; esac
  [ -n "$url" ] || url="${GK3_INPUT_BASE_URL%/}/$name"
  dst="$GK3_INPUTS/$name"
  case "$name" in src/*) dst="$GK3_SRC/${name#src/}" ;; esac

  if [ -f "$dst" ]; then
    have=$(sha256sum "$dst" | cut -d' ' -f1)
    if [ "$have" = "$sha" ]; then echo "  已有 $name"; skip=$((skip+1)); continue; fi
    echo "  sha 不符，重新下载 $name"
  fi
  echo "  下载 $name <- $url"
  if curl -fL --retry 3 -o "$dst.part" "$url"; then
    mv "$dst.part" "$dst"
    got=$(sha256sum "$dst" | cut -d' ' -f1)
    if [ "$got" != "$sha" ]; then echo "  FAIL $name sha 不符（$got）"; fail=$((fail+1)); continue; fi
    ok=$((ok+1))
  else
    echo "  FAIL 下载失败 $name"; rm -f "$dst.part"; fail=$((fail+1))
  fi
done < "$MAN"

echo "完成：下载 $ok，跳过 $skip，失败 $fail"
[ "$fail" -eq 0 ] || exit 1
echo FETCH_OK
