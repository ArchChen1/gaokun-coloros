#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
T=${TMPDIR:-/tmp}/odm-inspect
mkdir -p "$T"
cdn_odm=$(command -v simg2img)
ctx_odm=$(command -v fsck.erofs)
raw="$T/original-odm.raw"
if [ ! -f "$raw" ]; then "$cdn_odm" "$B/sparse/odm.img" "$raw"; fi
ls -lh "$raw"
mkdir -p "$T/original"
if [ ! -d "$T/original/etc" ]; then "$ctx_odm" --extract="$T/original" "$raw"; fi
echo '===== ORIGINAL ODM VINTF ====='
find "$T/original/etc/vintf" -maxdepth 4 -type f -printf '%P %s\n' 2>/dev/null | sort | head -200
echo "vintf_count=$(find "$T/original/etc/vintf" -type f 2>/dev/null | wc -l)"
echo '===== ORIGINAL ODM ETC TOP ====='
find "$T/original/etc" -maxdepth 2 -printf '%y %P\n' 2>/dev/null | sort | head -160