#!/bin/bash
# 补丁：vendor 的 C2 HAL 拉起修复（唯一改动 = etc/init/android.hardware.media.c2-service-v4l2.rc）
#
# 之前 rc 里是 `disabled`，没有任何东西会启动这个 HAL，于是硬件编解码整条链是死的；
# 改成声明 AIDL 接口后，init 会在客户端连上时按需拉起。
#
# 输入 = C2 之前的 vendor.img（5a5853c5…）；输出与账本产物 dd574c17… **内容等价**。
#
# 注意：ext4 镜像做不到字节级复现 —— 即使只改一个文件，mount rw / umount 也会把
# superblock 的 s_mtime / s_wtime / mount state 写进去，sha 必然不同。所以这里验的是
# 「文件树完全一致」：可选的第三个参数给账本里的参考镜像，脚本会挂两边做 diff -r。
#
# 用法：
#   bash build/patches/p_vendor_c2.sh <vendor_pre.img> <out.img> [参考镜像]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
IN=${1:?用法: p_vendor_c2.sh <vendor_pre.img> <out.img> [参考镜像]}
OUT=${2:?}
REF=${3:-}
IN_SHA=5a5853c516b507b1587552a57c1ca460181bdcef7b590af135cf9ade6e652e82   # C2 之前
OUT_SHA=dd574c1756496e2fdf598748600da5229862fdef3a1bc8a591a5685f08c0defb  # C2 之后
FILE=etc/init/android.hardware.media.c2-service-v4l2.rc
SRC="$HERE/vendor_c2/$FILE"
# 该文件在原镜像里的时间戳（字节级复现要靠它，ext4 原位改写不会动 inode 号）
MTIME='2026-11-25 14:59:56.617501665'

got=$(sha256sum "$IN" | cut -d' ' -f1)
if [ "$got" != "$IN_SHA" ]; then
    echo "输入不是 C2 之前的 vendor（sha $got != $IN_SHA），拒绝改" >&2
    exit 1
fi
[ -f "$SRC" ] || { echo "缺补丁文件 $SRC" >&2; exit 1; }

cp -f "$IN" "$OUT"
TMP=$(mktemp -d)
trap 'mountpoint -q "$TMP/m" && umount "$TMP/m"; rmdir "$TMP/m" "$TMP" 2>/dev/null || true' EXIT
mkdir -p "$TMP/m"
mount -o loop,rw "$OUT" "$TMP/m"
install -m 644 -o 0 -g 0 "$SRC" "$TMP/m/$FILE"
touch -d "$MTIME" "$TMP/m/$FILE"
sync
umount "$TMP/m"

got=$(sha256sum "$OUT" | cut -d' ' -f1)
if [ "$got" = "$OUT_SHA" ]; then
    echo "OK  vendor C2 补丁（字节级复现）：$IN -> $OUT  sha $OUT_SHA"
    exit 0
fi

# 字节不同是 ext4 的常态（superblock 时间戳），改验文件树
if [ -z "$REF" ]; then
    echo "输出 sha $got 与账本 $OUT_SHA 不同（ext4 时间戳所致），但未给参考镜像，无法验内容等价" >&2
    exit 2
fi
[ -f "$REF" ] || { echo "参考镜像不存在: $REF" >&2; exit 1; }
A=$(mktemp -d); B=$(mktemp -d)
trap 'umount "$A" 2>/dev/null; umount "$B" 2>/dev/null; rmdir "$A" "$B" 2>/dev/null; true' EXIT
mount -o loop,ro "$OUT" "$A"; mount -o loop,ro "$REF" "$B"
if diff -rq --no-dereference "$A" "$B" > /tmp/p_vendor_c2.diff 2>&1; then
    echo "OK  vendor C2 补丁（内容等价）：文件树与参考镜像一致；镜像 sha $got（ext4 时间戳使字节不同）"
else
    echo "FAIL 输出与参考镜像的文件树不同：" >&2
    head -20 /tmp/p_vendor_c2.diff >&2
    exit 3
fi
