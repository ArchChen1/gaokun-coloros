#!/bin/bash
# 补丁：删掉 odm 里那个空的 media_codecs_c2.xml，重打 odm.erofs。
#
# 症状：C2 HAL 已注册成功、也真的在枚举 iris 组件，但框架一律判
#       "component 'c2.v4l2.*' not found in xml"，硬件编解码组件数 0。
# 真因：MediaCodecsXmlParser 按 /odm/etc → /vendor/etc → /system/etc 找同名文件，
#       命中第一个就停。OPPO 在 odm 放了一个 791 B 的空壳（全文只有
#       <Included></Included>，零条声明），把我们装在 vendor 的 6904 B 配置顶掉了。
#       开机日志实证：只 parsing /odm/etc/media_codecs_c2.xml，vendor 那份从未打开。
#
# 用法：bash build/patches/p_odm_drop_empty_c2_xml.sh
#   TREE=/home/cenmin/v50-build/odm   odm 分区树（必须在 WSL ext4 上，带 xattr）
#   CUR=/mnt/e/gk3-coloros/work/parts_odm/odm.erofs   当前已刷入的镜像（用来验树没漂）
#   OUT_DIR=/mnt/e/gk3-coloros/work/parts_odm2
#
# 闸门：
#   1. 树不能在 /mnt（drvfs 丢 xattr/权限）
#   2. 删之前：当前镜像解包后与树逐条 diff 必须为 0（确认树没漂）
#   3. 被删文件必须确实是那个空壳（尺寸 + 无 MediaCodec 声明）
#   4. 重打后 dump.erofs 断言 /etc Xattr size != 0，且该文件已不存在
#   5. 重打后再解包，与树逐条 diff 必须为 0

set -euo pipefail

REPO=${REPO:-/mnt/e/gk3-coloros}
TREE=${TREE:-/home/cenmin/v50-build/odm}
CUR=${CUR:-$REPO/work/parts_odm/odm.erofs}
OUT_DIR=${OUT_DIR:-$REPO/work/parts_odm2}
FSK=${FSK:-/home/cenmin/toolchain/erofs-install/bin/fsck.erofs}
MKFS=${MKFS:-/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs}
DUMP=${DUMP:-/home/cenmin/toolchain/erofs-install/bin/dump.erofs}

UUID=c396ea80-c33f-4219-802e-fb354adcfbb1
LABEL=odm
CUR_SHA=7500129e857a261beb0184c142b3f594db50027529c0acbdd20dc78ec6dfc951
REL=etc/media_codecs_c2.xml

echo "== 0. 前置检查"
case "$TREE" in
    /mnt/*) echo "   !! 树不能放在 /mnt（drvfs 不保存 xattr/权限）"; exit 2 ;;
esac
[ -d "$TREE" ] || { echo "   !! 树不存在：$TREE"; exit 2; }
[ -s "$CUR" ] || { echo "   !! 找不到当前镜像：$CUR"; exit 2; }
mkdir -p "$OUT_DIR"
df -h / | tail -1
FREE_G=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
[ "$FREE_G" -ge 2 ] || { echo "   !! WSL 盘只剩 ${FREE_G}G，先清空间"; exit 2; }
got=$(sha256sum "$CUR" | cut -d' ' -f1)
[ "$got" = "$CUR_SHA" ] || { echo "   !! 当前镜像不是账本基线（$got）"; exit 2; }
getfattr -n security.selinux "$TREE/etc" >/dev/null 2>&1 || {
    echo "   !! 树的 /etc 没有 security.selinux"; exit 2; }
echo "   树 $TREE 条目 $(find "$TREE" -mindepth 1 | wc -l)"

echo "== 1. 确认要删的确实是空壳"
F="$TREE/$REL"
[ -f "$F" ] || { echo "   !! 树里没有 $REL"; exit 3; }
SZ_F=$(stat -c%s "$F")
echo "   $REL  $SZ_F B"
[ "$SZ_F" -eq 791 ] || { echo "   !! 尺寸不是 791 B，内容可能已变，停"; exit 3; }
if grep -q 'MediaCodec\|MediaCodecs' "$F"; then
    echo "   !! 文件里有编解码器声明，不是空壳，停"; exit 3
fi
echo "   全文（去掉注释）："
sed 's/<!--.*-->//' "$F" | tr -d ' \n' | sed 's/^/     /'
echo

echo "== 2. 删前闸门：当前镜像内容必须与树完全一致"
PRE="$OUT_DIR/pre-odm"
rm -rf "$PRE"; mkdir -p "$PRE"
if ! "$FSK" --extract="$PRE" --xattrs "$CUR" > "$OUT_DIR/pre-odm.log" 2>&1; then
    echo "   !! 当前镜像解包失败"; tail -3 "$OUT_DIR/pre-odm.log"; rm -rf "$PRE"; exit 4
fi
(cd "$PRE" && find . | sort) > "$OUT_DIR/list-odm-cur.txt"
(cd "$TREE" && find . | sort) > "$OUT_DIR/list-odm-tree-before.txt"
d0=$(diff "$OUT_DIR/list-odm-cur.txt" "$OUT_DIR/list-odm-tree-before.txt" | wc -l)
echo "   当前镜像条目 $(find "$PRE" -mindepth 1 | wc -l)，与树差异 $d0 行"
[ "$d0" -eq 0 ] || { echo "   !! 树与已刷入镜像不一致，停"; rm -rf "$PRE"; exit 4; }
rm -rf "$PRE"

echo "== 3. 删除"
rm -f "$F"
[ ! -e "$F" ] || { echo "   !! 删除失败"; exit 5; }
echo "   已删 $REL，树剩 $(find "$TREE" -mindepth 1 | wc -l) 条目"

echo "== 4. 重打 odm.erofs"
OUT="$OUT_DIR/odm.erofs"
rm -f "$OUT"
if ! "$MKFS" -zlz4 -b4096 -C65536 -L "$LABEL" -U "$UUID" "$OUT" "$TREE" > "$OUT_DIR/mkfs-odm.log" 2>&1; then
    echo "   !! mkfs 失败，看 $OUT_DIR/mkfs-odm.log"; tail -3 "$OUT_DIR/mkfs-odm.log"; exit 6
fi
SZ=$(stat -c%s "$OUT")
echo "   $SZ B（原 2131329024 B，差 $((SZ - 2131329024)) B）"
"$FSK" "$OUT" >/dev/null 2>&1 || { echo "   !! fsck 报错"; exit 7; }

echo "== 5. 镜像元数据闸门"
xs=$("$DUMP" --path=/etc "$OUT" 2>/dev/null | awk '/Xattr size:/{print $NF}')
echo "   /etc Xattr size = ${xs:-?}"
[ "${xs:-0}" != "0" ] || { echo "   !! 镜像没有 xattr（SELinux 标签丢了）"; exit 7; }
# dump.erofs 对不存在的路径也返回 0（只打 <E> read inode failed），
# 所以必须看输出内容，不能看退出码。
if "$DUMP" --path="/$REL" "$OUT" 2>&1 | grep -q 'regular file'; then
    echo "   !! 镜像里 $REL 还在"; exit 7
fi
echo "   /$REL 已不在镜像里"
# 充电那两个 so 必须还在（别把上一轮的成果打丢了）
for f in libhidltransport.so android.hardware.sensors-V3-ndk.so; do
    "$DUMP" --path="/lib64/$f" "$OUT" 2>/dev/null | tr '\n' ' ' | grep -q 'regular file' \
        || { echo "   !! /lib64/$f 丢了"; exit 7; }
done
echo "   充电两个 so 仍在"
uuid=$("$DUMP" -s "$OUT" 2>/dev/null | awk '/Filesystem UUID:/{print $NF}')
[ "$uuid" = "$UUID" ] || { echo "   !! UUID 变了：$uuid"; exit 7; }
echo "   UUID $uuid 保持"

echo "== 6. 解包自检：镜像内容必须与树逐条一致"
CHK="$OUT_DIR/chk-odm"
rm -rf "$CHK"; mkdir -p "$CHK"
if ! "$FSK" --extract="$CHK" "$OUT" > "$OUT_DIR/chk-odm.log" 2>&1; then
    echo "   !! 解包自检失败"; tail -3 "$OUT_DIR/chk-odm.log"; rm -rf "$CHK"; exit 8
fi
(cd "$CHK" && find . | sort) > "$OUT_DIR/list-odm-image.txt"
(cd "$TREE" && find . | sort) > "$OUT_DIR/list-odm-tree.txt"
d=$(diff "$OUT_DIR/list-odm-image.txt" "$OUT_DIR/list-odm-tree.txt" | wc -l)
echo "   镜像条目 $(find "$CHK" -mindepth 1 | wc -l)，与树差异 $d 行"
[ "$d" -eq 0 ] || { echo "   !! 镜像与树不一致"; rm -rf "$CHK"; exit 8; }
# 与删前的唯一差异必须正好是少了那一个文件
dd=$(diff "$OUT_DIR/list-odm-tree-before.txt" "$OUT_DIR/list-odm-tree.txt" || true)
echo "   与删前的差异："; printf '%s\n' "$dd" | sed 's/^/     /'
[ "$(printf '%s\n' "$dd" | grep -c '^[<>]')" -eq 1 ] || { echo "   !! 差异不止一个文件"; rm -rf "$CHK"; exit 8; }
rm -rf "$CHK"

echo "== 7. 产物"
ls -l "$OUT"
sha256sum "$OUT"
echo "== 完成。把这个 sha 写进账本再出包（删前基线 $CUR_SHA）。"