#!/bin/bash
# 补丁：删掉官方预装的几款"运营类"应用（不进设置、不影响系统功能），并把
# my_stock / system_ext 两个分区重新打成 erofs。
#
# 为什么必须重打分区：这些 APK 就在 my_stock/del-app 与 system_ext/app 里，
# 运行时卸载只是把 /data 里的副本删掉，下次刷机/恢复出厂又会回来。
#
# 删除清单在 build/patches/strip-preinstalled.txt，一行一个（相对分区根的路径）。
#
# 用法：bash build/patches/p_strip_preinstalled.sh
#   TREE_BASE=/home/cenmin/strip/tree       解包出的两棵分区树（不存在时自动解）
#   OUT_DIR=/home/cenmin/coloros-build/current/parts/strip
#
# 自检：fsck clean、解包后确认清单里的路径都不存在、体积不超分区上限。

set -euo pipefail

REPO=${REPO:-/mnt/e/gk3-coloros}
TREE_BASE=${TREE_BASE:-/home/cenmin/strip/tree}
OUT_DIR=${OUT_DIR:-/mnt/e/gk3-coloros/work/parts_strip}
FSK=${FSK:-/home/cenmin/toolchain/erofs-install/bin/fsck.erofs}
MKFS=${MKFS:-/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs}
DUMP=${DUMP:-/home/cenmin/toolchain/erofs-install/bin/dump.erofs}
LIST="$REPO/build/patches/strip-preinstalled.txt"

LIMIT_my_stock=4026658816
LIMIT_system_ext=986378240
UUID_my_stock=B9835846-6C8C-535D-A543-7B117AF90EAA
UUID_system_ext=DF47FE2B-FFC3-F155-A38E-9D5072A9CE45

SRC_my_stock=/home/cenmin/coloros-build/v52/my_stock_a_v52.erofs
SRC_system_ext=/home/cenmin/coloros-build/v49/src/system_ext_a.img

[ -f "$LIST" ] || { echo "缺删除清单：$LIST"; exit 1; }
mkdir -p "$OUT_DIR" "$TREE_BASE"

# 树必须完整：条目数写死（源镜像原始条目数），只在"首次解包"时校验。
# 解包静默缺文件曾导致开机卡死；重复运行（树已删过）不做这项校验。
EXPECT_my_stock=${EXPECT_my_stock:-1091}
EXPECT_system_ext=${EXPECT_system_ext:-3949}

extract_if_missing() {
    local name=$1 img=$2
    if [ ! -d "$TREE_BASE/$name" ]; then
        echo "   解包 $name（首次，带 xattr）"
        mkdir -p "$TREE_BASE/$name"
        if ! "$FSK" --extract="$TREE_BASE/$name" --xattrs "$img" > "$OUT_DIR/extract-$name.log" 2>&1; then
            echo "   !! 解包失败 $name，看 $OUT_DIR/extract-$name.log"; exit 2
        fi
        local exp_var="EXPECT_$name"; local exp=${!exp_var}
        local got=$(find "$TREE_BASE/$name" -mindepth 1 | wc -l)
        echo "   条目 $got / 期望 $exp"
        [ "$exp" -eq 0 ] || [ "$got" -eq "$exp" ] || { echo "   !! $name 树不完整（解包时磁盘满会静默丢文件）"; exit 2; }
    fi
    # 树必须带 SELinux 标签：drvfs（/mnt/*）不支持 xattr，落在那里会全丢，开机会卡死
    case "$TREE_BASE" in
        /mnt/*) echo "   !! 树不能放在 /mnt（drvfs 不保存 xattr/权限）"; exit 2 ;;
    esac
    if ! getfattr -n security.selinux "$TREE_BASE/$name/etc" >/dev/null 2>&1; then
        echo "   !! $name 树没有 security.selinux（解包漏了 --xattrs 或盘不支持），删掉树重来"; exit 2
    fi
}

echo "== 1. 准备分区树"
mkdir -p "$OUT_DIR"
df -h / | tail -1
FREE_G=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
[ "$FREE_G" -ge 2 ] || { echo "   !! WSL 盘只剩 ${FREE_G}G，先清空间"; exit 2; }
extract_if_missing my_stock "$SRC_my_stock"
extract_if_missing system_ext "$SRC_system_ext"

echo "== 2. 按清单删除"
DELETED=0
DEL_my_stock=0
DEL_system_ext=0
while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    part=${line%%:*}
    rel=${line#*:}
    rel=${rel%%#*}
    rel=${rel%"${rel##*[! ]}"}
    t="$TREE_BASE/$part/$rel"
    if [ -e "$t" ]; then
        n=$(find "$t" | wc -l)          # 这一项含几层条目（决定镜像应少多少）
        rm -rf "$t"
        DELETED=$((DELETED+1))
        eval "DEL_$part=\$((DEL_$part + n))"
    else
        echo "   !! 清单项已经不存在（换基线后要更新清单）：$line"
    fi
done < "$LIST"
echo "   删除 $DELETED 项（my_stock 少 $DEL_my_stock 条目，system_ext 少 $DEL_system_ext 条目）"
if [ "$DELETED" -eq 0 ]; then echo "   树里已经没有清单项（重复运行），直接重打"; fi

echo "== 3. 重打两个分区"
for p in my_stock system_ext; do
    case $p in
        my_stock)    U=$UUID_my_stock;    L=$LIMIT_my_stock ;;
        system_ext)  U=$UUID_system_ext;  L=$LIMIT_system_ext ;;
    esac
    out="$OUT_DIR/$p.erofs"
    rm -f "$out"
    if ! "$MKFS" -zlz4 -b4096 -C65536 -L "$p" -U "$U" "$out" "$TREE_BASE/$p" > "$OUT_DIR/mkfs-$p.log" 2>&1; then
        echo "   !! $p mkfs 失败，看 $OUT_DIR/mkfs-$p.log"; tail -3 "$OUT_DIR/mkfs-$p.log"; exit 4
    fi
    SZ=$(stat -c%s "$out")
    echo "   $p: $SZ B（上限 $L B）"
    if [ "$SZ" -gt "$L" ]; then echo "   !! $p 超过分区上限"; exit 4; fi
    "$FSK" "$out" >/dev/null 2>&1 || { echo "   !! $p fsck 报错"; exit 5; }
    # SELinux 标签必须真的进了镜像（Xattr size 为 0 就是丢了，装上去会卡开机）
    xs=$("$DUMP" --path=/etc "$out" 2>/dev/null | awk '/Xattr size:/{print $NF}')
    echo "   $p /etc Xattr size = ${xs:-?}"
    if [ "${xs:-0}" = "0" ]; then echo "   !! $p 镜像没有 xattr（SELinux 标签丢了）"; exit 5; fi
done

echo "== 4. 自检：解包出来的镜像必须和树逐条一致（解到 E: 避免占 WSL 盘）"
for p in my_stock system_ext; do
    chk="$OUT_DIR/chk-$p"
    rm -rf "$chk"; mkdir -p "$chk"
    if ! "$FSK" --extract="$chk" "$OUT_DIR/$p.erofs" > "$OUT_DIR/chk-$p.log" 2>&1; then
        echo "   !! $p 解包自检失败（镜像坏了/写了一半）"; tail -3 "$OUT_DIR/chk-$p.log"; rm -rf "$chk"; exit 6
    fi
    (cd "$chk" && find . | sort) > "$OUT_DIR/list-$p-image.txt"
    (cd "$TREE_BASE/$p" && find . | sort) > "$OUT_DIR/list-$p-tree.txt"
    d=$(diff "$OUT_DIR/list-$p-image.txt" "$OUT_DIR/list-$p-tree.txt" | wc -l)
    got=$(find "$chk" -mindepth 1 | wc -l)
    echo "   $p 镜像条目 $got，与树差异 $d 行"
    if [ "$d" -ne 0 ]; then echo "   !! $p 镜像与树不一致，见 $OUT_DIR/list-$p-*.txt"; rm -rf "$chk"; exit 7; fi
    rm -rf "$chk"
done
echo "   通过：清单里的东西都不在镜像里了"

echo "== 5. 体积与 sha"
ls -l "$OUT_DIR"
sha256sum "$OUT_DIR"/my_stock.erofs "$OUT_DIR"/system_ext.erofs
echo "== 完成。接下来把这两个 sha 写进账本再出包。"
