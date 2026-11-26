#!/usr/bin/env bash
# 在 vendor.img 副本里把 libcodec2_vndk.so 的 setSmpte2094_5 引用改成 WEAK，
# 让 C2 HAL 能在 ColorOS 的 odm libui 下链接成功。详见 build/patches/p_codec_libui_weak.py。
#
# 用法：bash build/patch_vendor_codec_libui.sh <源 vendor.img> <输出 vendor.img>
# 只写输出副本，不动源镜像；输出与源同样大小，可走增量 OTA。
set -euo pipefail

SRC=${1:?用法: patch_vendor_codec_libui.sh <源 vendor.img> <输出 vendor.img>}
OUT=${2:?用法: patch_vendor_codec_libui.sh <源 vendor.img> <输出 vendor.img>}
PATCH=/mnt/e/gk3-coloros/build/patches/p_codec_libui_weak.py
BASE_SHA=dd574c1756496e2fdf598748600da5229862fdef3a1bc8a591a5685f08c0defb

[ -s "$SRC" ] || { echo "找不到源镜像: $SRC"; exit 1; }
[ "$SRC" != "$OUT" ] || { echo "源与输出不能是同一个文件"; exit 1; }

echo "== 0. 前置"
got=$(sha256sum "$SRC" | cut -d' ' -f1)
[ "$got" = "$BASE_SHA" ] || { echo "  !! 源 vendor 不是账本基线（$got）"; exit 2; }
FREE_G=$(df -BG "$(dirname "$OUT")" 2>/dev/null || df -BG /mnt/e)
FREE_G=$(echo "$FREE_G" | tail -1 | awk '{print $4}' | tr -d 'G')
echo "  输出盘余量 ${FREE_G}G"
[ "$FREE_G" -ge 2 ] || { echo "  !! 空间不足"; exit 2; }

echo "== 1. 复制副本"
mkdir -p "$(dirname "$OUT")"
cp --reflink=auto "$SRC" "$OUT"
SZ_BEFORE=$(stat -c%s "$OUT")

MNT=$(mktemp -d)
trap 'umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT
mount -t ext4 -o loop,rw "$OUT" "$MNT"

LIB="$MNT/lib64/libcodec2_vndk.so"
[ -f "$LIB" ] || { echo "镜像里没有 $LIB"; exit 3; }

echo "== 2. 改前状态"
ls -l "$LIB"
getfattr -n security.selinux --only-values --absolute-names "$LIB" 2>/dev/null | sed 's/^/  label=/'
echo
SHA_BEFORE=$(sha256sum "$LIB" | cut -d' ' -f1)
readelf --dyn-syms -W "$LIB" | grep 'setSmpte2094_50EPK13native_handle' | sed 's/^/  /'

echo "== 3. 打补丁"
python3 "$PATCH" "$LIB"

echo "== 4. 改后核对"
SHA_AFTER=$(sha256sum "$LIB" | cut -d' ' -f1)
[ "$SHA_BEFORE" != "$SHA_AFTER" ] || { echo "  !! 库没变"; exit 4; }
readelf --dyn-syms -W "$LIB" | grep 'setSmpte2094_50EPK13native_handle' | sed 's/^/  /'
readelf --dyn-syms -W "$LIB" | grep 'setSmpte2094_50EPK13native_handle' | grep -q WEAK \
    || { echo "  !! 没变成 WEAK"; exit 4; }
ls -l "$LIB"
getfattr -n security.selinux --only-values --absolute-names "$LIB" 2>/dev/null | sed 's/^/  label=/'
echo

echo "== 5. 收尾"
umount "$MNT"
rmdir "$MNT"
trap - EXIT
e2fsck -fn "$OUT" >/dev/null 2>&1 && echo "  fsck clean" || { echo "  !! fsck 报错"; exit 5; }
SZ_AFTER=$(stat -c%s "$OUT")
[ "$SZ_BEFORE" = "$SZ_AFTER" ] || { echo "  !! 镜像尺寸变了"; exit 6; }
echo "  size $SZ_AFTER B（不变）"
sha256sum "$OUT"
echo "== 完成"