#!/usr/bin/env bash
# 在 vendor.img 副本里补 C2 HAL 的 VINTF 分片，让 servicemanager 允许注册
# android.hardware.media.c2.IComponentStore/default。
#
# 用法：bash build/patch_vendor_c2_vintf.sh <源 vendor.img> <输出 vendor.img>
# 只写输出副本，不动源镜像；输出与源同样大小，可走增量 OTA。
set -euo pipefail

SRC=${1:?用法: patch_vendor_c2_vintf.sh <源 vendor.img> <输出 vendor.img>}
OUT=${2:?用法: patch_vendor_c2_vintf.sh <源 vendor.img> <输出 vendor.img>}
BASE_SHA=6fa870afb7c173d5f3771e0ba83fefa6bbb24f391f8ae37d648a87a07187821c
NAME=android.hardware.media.c2-service-v4l2.xml

[ -s "$SRC" ] || { echo "找不到源镜像: $SRC"; exit 1; }
[ "$SRC" != "$OUT" ] || { echo "源与输出不能是同一个文件"; exit 1; }

echo "== 0. 前置"
got=$(sha256sum "$SRC" | cut -d' ' -f1)
[ "$got" = "$BASE_SHA" ] || { echo "  !! 源 vendor 不是账本基线（$got）"; exit 2; }
mkdir -p "$(dirname "$OUT")"
FREE_G=$(df -BG "$(dirname "$OUT")" | tail -1 | awk '{print $4}' | tr -d 'G')
echo "  输出盘余量 ${FREE_G}G"
[ "$FREE_G" -ge 2 ] || { echo "  !! 空间不足"; exit 2; }

echo "== 1. 复制副本"
cp --reflink=auto "$SRC" "$OUT"
SZ_BEFORE=$(stat -c%s "$OUT")

MNT=$(mktemp -d)
trap 'umount "$MNT" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true' EXIT
mount -t ext4 -o loop,rw "$OUT" "$MNT"

DIR="$MNT/etc/vintf/manifest"
[ -d "$DIR" ] || { echo "镜像里没有 $DIR"; exit 3; }
[ ! -e "$DIR/$NAME" ] || { echo "  分片已存在，无需重复补"; exit 3; }

echo "== 2. 镜像内余量与样板标签"
df -h "$MNT" | tail -1
REF="$DIR/android.hardware.thermal-service.gaokun3.xml"
[ -f "$REF" ] || REF=$(ls "$DIR"/*.xml | head -1)
LABEL=$(getfattr -n security.selinux --only-values --absolute-names "$REF" 2>/dev/null || true)
[ -n "$LABEL" ] || { echo "  !! 取不到样板 SELinux 标签"; exit 4; }
echo "  样板 $(basename "$REF")  label=$LABEL"
OWN=$(stat -c '%u:%g %a' "$REF")
echo "  样板 owner:mode = $OWN"

echo "== 3. 写入分片"
cat > "$DIR/$NAME" <<'XML'
<manifest version="9.0" type="device">
    <hal format="aidl">
        <name>android.hardware.media.c2</name>
        <version>1</version>
        <fqname>IComponentStore/default</fqname>
    </hal>
</manifest>
XML
chown 0:0 "$DIR/$NAME"
chmod 644 "$DIR/$NAME"
setfattr -n security.selinux -v "$LABEL" "$DIR/$NAME"

echo "== 4. 核对"
ls -l "$DIR/$NAME"
GL=$(getfattr -n security.selinux --only-values --absolute-names "$DIR/$NAME" 2>/dev/null || true)
echo "  label=$GL"
[ "$GL" = "$LABEL" ] || { echo "  !! 标签不一致"; exit 5; }
[ "$(stat -c '%u:%g %a' "$DIR/$NAME")" = "0:0 644" ] || { echo "  !! 属主或权限不对"; exit 5; }
python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1]); print('  XML 解析通过')" "$DIR/$NAME"
cat "$DIR/$NAME" | sed 's/^/  /'
echo "  manifest 目录共 $(ls "$DIR" | wc -l) 个分片"

echo "== 5. 收尾"
umount "$MNT"
rmdir "$MNT"
trap - EXIT
e2fsck -fn "$OUT" >/dev/null 2>&1 && echo "  fsck clean" || { echo "  !! fsck 报错"; exit 6; }
SZ_AFTER=$(stat -c%s "$OUT")
[ "$SZ_BEFORE" = "$SZ_AFTER" ] || { echo "  !! 镜像尺寸变了"; exit 7; }
echo "  size $SZ_AFTER B（不变）"
sha256sum "$OUT"
echo "== 完成"