#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
T=${TMPDIR:-/tmp}/odm-inspect
raw="$T/final-merged-odm.raw"
if [ ! -f "$raw" ]; then simg2img "$B/sparse/odm-final-merged.img" "$raw"; fi
ls -lh "$raw"
mkdir -p "$T/final-merged"
if [ ! -d "$T/final-merged/etc" ]; then fsck.erofs --extract="$T/final-merged" "$raw"; fi
echo '===== FINAL MERGED ODM VINTF ====='
find "$T/final-merged/etc/vintf" -maxdepth 4 -type f -printf '%P %s\n' 2>/dev/null | sort | head -200
echo "vintf_count=$(find "$T/final-merged/etc/vintf" -type f 2>/dev/null | wc -l)"
echo '===== FINAL MERGED ODM VINTF DIRS ====='
find "$T/final-merged/etc" -maxdepth 2 -type d -name 'vintf*' -printf '%p\n' 2>/dev/null
echo '===== ORIGINAL VS FINAL VINTF MANIFEST NAMES ====='
comm -23 <(cd "$T/original/etc/vintf" 2>/dev/null && find . -type f -printf '%P\n' | sort) <(cd "$T/final-merged/etc/vintf" 2>/dev/null && find . -type f -printf '%P\n' | sort) | head -100 || true