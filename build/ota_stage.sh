#!/usr/bin/env bash
# 把 current/parts 与 src 里的 13 个分区镜像收进一个 staging 目录，生成 B 槽写入脚本。
#
#   sudo -E bash build/ota_stage.sh                 # 默认槽 b，布局取 tools/ota/testdata/lp-layout.json
#   bash build/ota_stage.sh --layout /path/lp.json --slot b
#   bash build/ota_stage.sh --device                  # 顺带从真机现取布局（需要 adb，在 Windows 侧跑）
#
# 产物在 $GK3_WORKDIR/ota/：write_b.sh、verify_b.sh、ota-manifest.json、in/（13 个软链）
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/env.sh"

SLOT=b
LAYOUT="$REPO/tools/ota/testdata/lp-layout.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --slot) SLOT=$2; shift 2 ;;
    --layout) LAYOUT=$2; shift 2 ;;
    *) echo "未知参数 $1" >&2; exit 1 ;;
  esac
done

OUT="$GK3_WORKDIR/ota"
STAGE="$OUT/in"
mkdir -p "$STAGE"

# 分区 → 来源目录（与 tools/ota/slot_writer.py 的 DEFAULT_FILES 对齐）
# 优先硬链接：Windows 侧的 adb.exe 无法 stat WSL 的软链，推文件时要用真实 inode。
link() {  # <文件名> <源路径>
  [ -s "$2" ] || { echo "缺镜像 $2" >&2; exit 1; }
  rm -f "$STAGE/$1"
  ln "$2" "$STAGE/$1" 2>/dev/null || ln -s "$2" "$STAGE/$1"
}
for f in system.erofs odm.erofs vendor.img my_product.erofs my_stock.erofs; do link "$f" "$GK3_PARTS/$f"; done
for f in system_ext_a.img product_a.img my_manifest_a.img my_region_a.img \
         my_engineering_a.img my_heytap_a.img my_carrier_a.img my_bigball_a.img; do
  link "$f" "$GK3_SRC/$f"
done

echo "== staging（$STAGE）"
ls -lL "$STAGE" | tail -n +2 | awk '{printf "  %-24s %12d\n", $9, $5}'

python3 "$REPO/tools/ota/slot_writer.py" "$LAYOUT" --slot "$SLOT" --parts-dir "$STAGE" --out "$OUT"
echo OTA_STAGE_OK
