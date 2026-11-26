#!/bin/bash
# 补丁：给 odm/lib64 补上充电 HAL 缺的两个 so，并重打 odm.erofs。
#
# 症状：oplus_charger_hal_service 每秒 restarting，dumpsys battery 里
#       ChargerTechnology=-1、无 ICharger 服务。根因是 vendor 命名空间看不到
#       system 的库，链接依次缺 libjsoncpp.so（已在）、
#       android.hardware.sensors-V3-ndk.so、libhidltransport.so。
#
# 两个 so 随仓库带在 build/patches/odm_charger/lib64/（合计 114 KB），
# 脚本负责按正确的属主/权限/SELinux 标签放进树，再重打镜像。
#
# 用法：bash build/patches/p_odm_charger_libs.sh
#   TREE=/home/cenmin/v50-build/odm   odm 分区树（必须在 WSL ext4 上，带 xattr）
#   OUT_DIR=/mnt/e/gk3-coloros/work/parts_odm
#
# 闸门（都是上次卡开机事故换来的）：
#   1. 树不能在 /mnt（drvfs 丢 xattr/权限）
#   2. 树的 /etc 与新增 so 必须带 security.selinux
#   3. 重打后 dump.erofs 断言 Xattr size != 0
#   4. 重打后再解包，与树逐条 diff 必须为 0
#   5. 两个 so 必须真的在镜像里

set -euo pipefail

REPO=${REPO:-/mnt/e/gk3-coloros}
TREE=${TREE:-/home/cenmin/v50-build/odm}
OUT_DIR=${OUT_DIR:-/mnt/e/gk3-coloros/work/parts_odm}
FSK=${FSK:-/home/cenmin/toolchain/erofs-install/bin/fsck.erofs}
MKFS=${MKFS:-/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs}
DUMP=${DUMP:-/home/cenmin/toolchain/erofs-install/bin/dump.erofs}
SRC="$REPO/build/patches/odm_charger/lib64"

UUID=c396ea80-c33f-4219-802e-fb354adcfbb1   # 原厂 odm 的 UUID，必须保持
LABEL=odm
BASE_SHA=5f014b79a4e68ee9521dee46874dff30e282b9a39522bf7f9e8da3971e44b11e  # 补库前的 odm.erofs
BASE_SIZE=2131279872
# super 未分配余量 1.59 GB，这里只允许 odm 长大 64 MB，超了说明树里混进了别的东西
MAX_GROWTH=$((64 << 20))

LIBS="libhidltransport.so android.hardware.sensors-V3-ndk.so"

echo "== 0. 前置检查"
case "$TREE" in
    /mnt/*) echo "   !! 树不能放在 /mnt（drvfs 不保存 xattr/权限）"; exit 2 ;;
esac
[ -d "$TREE" ] || { echo "   !! 树不存在：$TREE"; exit 2; }
mkdir -p "$OUT_DIR"
df -h / | tail -1
FREE_G=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
[ "$FREE_G" -ge 2 ] || { echo "   !! WSL 盘只剩 ${FREE_G}G，先清空间"; exit 2; }
getfattr -n security.selinux "$TREE/etc" >/dev/null 2>&1 || {
    echo "   !! 树的 /etc 没有 security.selinux（解包漏了 --xattrs 或盘不支持）"; exit 2; }
echo "   树 $TREE 条目 $(find "$TREE" -mindepth 1 | wc -l)"

echo "== 1. 放两个 so（644 root:root，标签 system_file，与同目录 libjsoncpp.so 一致）"
for f in $LIBS; do
    [ -f "$SRC/$f" ] || { echo "   !! 仓库缺补丁文件 $SRC/$f"; exit 2; }
    install -m 644 -o 0 -g 0 "$SRC/$f" "$TREE/lib64/$f"
    # install 不会带 SELinux 标签，必须显式打；否则 enforcing 下加载会被拒
    if command -v setfattr >/dev/null 2>&1; then
        setfattr -n security.selinux -v 'u:object_r:system_file:s0' "$TREE/lib64/$f"
    else
        chcon u:object_r:system_file:s0 "$TREE/lib64/$f"
    fi
    got=$(getfattr -n security.selinux --only-values "$TREE/lib64/$f" 2>/dev/null || true)
    [ "$got" = "u:object_r:system_file:s0" ] || { echo "   !! $f 标签没打上（得到 '$got'）"; exit 3; }
    echo "   $f  $(stat -c '%s B mode=%a %u:%g' "$TREE/lib64/$f")  label=$got"
done

echo "== 2. 重打 odm.erofs"
OUT="$OUT_DIR/odm.erofs"
rm -f "$OUT"
if ! "$MKFS" -zlz4 -b4096 -C65536 -L "$LABEL" -U "$UUID" "$OUT" "$TREE" > "$OUT_DIR/mkfs-odm.log" 2>&1; then
    echo "   !! mkfs 失败，看 $OUT_DIR/mkfs-odm.log"; tail -3 "$OUT_DIR/mkfs-odm.log"; exit 4
fi
SZ=$(stat -c%s "$OUT")
GROWTH=$((SZ - BASE_SIZE))
echo "   $SZ B（补库前 $BASE_SIZE B，增长 $GROWTH B）"
[ "$GROWTH" -le "$MAX_GROWTH" ] || { echo "   !! 增长超过 $MAX_GROWTH B，树里可能混了别的东西"; exit 4; }
"$FSK" "$OUT" >/dev/null 2>&1 || { echo "   !! fsck 报错"; exit 5; }

echo "== 3. 镜像元数据闸门"
xs=$("$DUMP" --path=/etc "$OUT" 2>/dev/null | awk '/Xattr size:/{print $NF}')
echo "   /etc Xattr size = ${xs:-?}"
[ "${xs:-0}" != "0" ] || { echo "   !! 镜像没有 xattr（SELinux 标签丢了）"; exit 5; }
for f in $LIBS; do
    line=$("$DUMP" --path="/lib64/$f" "$OUT" 2>/dev/null | tr '\n' ' ')
    case "$line" in
        *"regular file"*) : ;;
        *) echo "   !! 镜像里找不到 /lib64/$f"; exit 5 ;;
    esac
    lx=$(printf '%s' "$line" | sed -n 's/.*Xattr size: *\([0-9]*\).*/\1/p')
    echo "   /lib64/$f Xattr size = ${lx:-?}"
    [ "${lx:-0}" != "0" ] || { echo "   !! $f 在镜像里没有标签"; exit 5; }
done
uuid=$("$DUMP" -s "$OUT" 2>/dev/null | awk '/Filesystem UUID:/{print $NF}')
[ "$uuid" = "$UUID" ] || { echo "   !! UUID 变了：$uuid"; exit 5; }
echo "   UUID $uuid 保持"

echo "== 4. 解包自检：镜像内容必须与树逐条一致"
CHK="$OUT_DIR/chk-odm"
rm -rf "$CHK"; mkdir -p "$CHK"
if ! "$FSK" --extract="$CHK" "$OUT" > "$OUT_DIR/chk-odm.log" 2>&1; then
    echo "   !! 解包自检失败"; tail -3 "$OUT_DIR/chk-odm.log"; rm -rf "$CHK"; exit 6
fi
(cd "$CHK" && find . | sort) > "$OUT_DIR/list-odm-image.txt"
(cd "$TREE" && find . | sort) > "$OUT_DIR/list-odm-tree.txt"
d=$(diff "$OUT_DIR/list-odm-image.txt" "$OUT_DIR/list-odm-tree.txt" | wc -l)
echo "   镜像条目 $(find "$CHK" -mindepth 1 | wc -l)，与树差异 $d 行"
[ "$d" -eq 0 ] || { echo "   !! 镜像与树不一致，见 $OUT_DIR/list-odm-*.txt"; rm -rf "$CHK"; exit 7; }
rm -rf "$CHK"

echo "== 5. 产物"
ls -l "$OUT"
sha256sum "$OUT"
echo "== 完成。把这个 sha 写进账本再出包（补库前基线 $BASE_SHA）。"