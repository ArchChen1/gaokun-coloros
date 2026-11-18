#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
echo '===== ODM IMAGE FILES ====='
ls -lh "$B/sparse/odm.img" "$B/sparse/odm-final.img" "$B/sparse/odm-final-merged.img" 2>/dev/null || true
file "$B/sparse/odm.img" "$B/sparse/odm-final.img" "$B/sparse/odm-final-merged.img" 2>/dev/null || true
echo '===== EXTRACT ORIGINAL ODM LIST ====='
for img in "$B/sparse/odm.img" "$B/sparse/odm-final-merged.img"; do
  if [ -f "$img" ]; then
    echo "--- $img ---"
    fsck.erofs --extract=/tmp/odm-check-$(basename "$img" | tr '.' '_') "$img" >/tmp/erofs.log 2>&1 || { cat /tmp/erofs.log; continue; }
    d=/tmp/odm-check-$(basename "$img" | tr '.' '_')
    find "$d/etc/vintf" -maxdepth 4 -type f -printf '%P %s\n' 2>/dev/null | sort | head -100 || true
    echo "vintf_count=$(find "$d/etc/vintf" -type f 2>/dev/null | wc -l)"
    find "$d/etc/init" -maxdepth 3 -type f -printf '%P %s\n' 2>/dev/null | sort | head -80 || true
  fi
done