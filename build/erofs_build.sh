#!/usr/bin/env bash
# 从仓库内固定的源码包构建 erofs-utils 1.9.4，装到 $GK3_WORKDIR/toolchain/erofs-install。
#
# 为什么要自己编：GitHub 运行器自带的 erofs-utils 是 1.7.1，同输入产出的 system/odm 分区体积差几百 KB，
# super.img 的 sha 就对不上。同一个版本的 mkfs 才谈得上“可复现”。
#
# 幂等：$PREFIX/.version 里写着 1.9.4 就直接跳过。
# 用法：sudo -E bash build/erofs_build.sh      （deps.sh 会自动调用）
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/env.sh"

VER=1.9.4
TAR="$REPO/tools/toolchain/erofs-utils-v$VER.tar.gz"
TAR_SHA=ab97e155a0f6e6fd9c5975b66a5a4eca2caf9562b2713e399ab8666ed7363918
PREFIX="${GK3_EROFS_PREFIX:-$GK3_WORKDIR/toolchain/erofs-install}"
WORK="$GK3_WORKDIR/toolchain/erofs-build"

[ -f "$TAR" ] || { echo "缺源码包 $TAR" >&2; exit 1; }
got=$(sha256sum "$TAR" | cut -d' ' -f1)
[ "$got" = "$TAR_SHA" ] || { echo "源码包 sha 不符：$got" >&2; exit 1; }

if [ -f "$PREFIX/.version" ] && [ "$(cat "$PREFIX/.version")" = "$VER" ]; then
  echo "  OK   erofs-utils $VER 已在 $PREFIX"
  exit 0
fi

echo "== 构建 erofs-utils $VER（$PREFIX）"
mkdir -p "$WORK"
rm -rf "$WORK"/erofs-*
tar -C "$WORK" -xzf "$TAR"
SRC=$(find "$WORK" -maxdepth 1 -mindepth 1 -type d -print -quit)
[ -n "$SRC" ] || { echo "解包后没有源码目录" >&2; exit 1; }

cd "$SRC"
[ -x ./configure ] || ./autogen.sh > "$GK3_WORKDIR/toolchain/erofs-autogen.log" 2>&1 \
  || { tail -20 "$GK3_WORKDIR/toolchain/erofs-autogen.log" >&2; exit 1; }
./configure --prefix="$PREFIX" \
  --disable-fuse-support --without-selinux --without-libdeflate \
  > "$GK3_WORKDIR/toolchain/erofs-configure.log" 2>&1 \
  || { tail -30 "$GK3_WORKDIR/toolchain/erofs-configure.log" >&2; exit 1; }
make -j"$(nproc)" > "$GK3_WORKDIR/toolchain/erofs-make.log" 2>&1 \
  || { tail -30 "$GK3_WORKDIR/toolchain/erofs-make.log" >&2; exit 1; }
make install > "$GK3_WORKDIR/toolchain/erofs-install.log" 2>&1
printf '%s' "$VER" > "$PREFIX/.version"
echo "  装好：$PREFIX/bin/{mkfs,fsck,dump}.erofs"
echo EROFS_BUILD_OK
