#!/usr/bin/env bash
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
P=/home/cenmin/coloros-build
SRC=$P/v49/src
mount_ro() { # dir img
  local d="$1" i="$2"
  mkdir -p "$d"; umount "$d" 2>/dev/null
  mount -t ext4 -o loop,ro "$i" "$d" 2>/dev/null && { echo "mounted $i -> $d"; return 0; }
  mount -t erofs -o loop,ro "$i" "$d" 2>/dev/null && { echo "mounted(erofs) $i -> $d"; return 0; }
  echo "skip $i (无法挂载)"; return 1
}
mount_ro /mnt/cv "$P/current/parts/vendor.img"
mount_ro /mnt/se "$SRC/system_ext_a.img"
mount_ro /mnt/pd "$SRC/product_a.img"
mount_ro /mnt/mp "$P/v52/my_product_a_v52b.erofs"
mount_ro /mnt/ms "$P/v52/my_stock_a_v52.erofs"
python3 "$SCRIPT_DIR/charger_hal_deps.py"
for d in /mnt/cv /mnt/se /mnt/pd /mnt/mp /mnt/ms; do umount "$d" 2>/dev/null; done
