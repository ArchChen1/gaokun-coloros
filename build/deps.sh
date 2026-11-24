#!/usr/bin/env bash
# 安装构建依赖（Debian/Ubuntu，WSL 亦可）。只做检查与安装，不改动系统其它配置。
# erofs-utils 不用发行版自带的（版本不同 → 分区体积不同 → super.img 的 sha 不同），
# 统一从仓库内的源码包编 1.9.4 到 $GK3_WORKDIR/toolchain/erofs-install。
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SUDO=${SUDO:-sudo}

need_pkgs="python3 python3-pip curl git zstd e2fsprogs attr android-sdk-libsparse-utils clang util-linux erofs-utils"
# 编 erofs-utils 需要
need_pkgs="$need_pkgs build-essential autoconf automake libtool pkg-config liblz4-dev liblzma-dev zlib1g-dev uuid-dev"

if ! command -v apt-get >/dev/null; then
  echo "非 Debian/Ubuntu：请自行安装 $need_pkgs" >&2
  exit 1
fi

miss=""
for p in $need_pkgs; do
  dpkg -s "$p" >/dev/null 2>&1 || miss="$miss $p"
done
if [ -n "$miss" ]; then
  echo "安装缺失包:$miss"
  $SUDO apt-get update -qq
  # shellcheck disable=SC2086
  $SUDO apt-get install -y -qq $miss
fi

echo '== erofs-utils 1.9.4（钉版，从源码编）'
bash "$SCRIPT_DIR/erofs_build.sh"
# erofs_build.sh 可能刚装好工具，重新 source 一遍取到 GK3_MKFS_EROFS
# shellcheck disable=SC1091
. "$SCRIPT_DIR/env.sh"

echo '== 工具检查'
for t in "$GK3_MKFS_EROFS" "$GK3_FSCK_EROFS"; do
  if [ -x "$t" ]; then printf '  OK   %s\n' "$t"; else printf '  FAIL 缺 %s\n' "$t"; exit 1; fi
done
for t in simg2img zstd python3; do
  if command -v "$t" >/dev/null; then printf '  OK   %-12s %s\n' "$t" "$(command -v "$t")"; else printf '  FAIL %s 未找到\n' "$t"; exit 1; fi
done
printf '  erofs 版本: %s\n' "$(cat "${GK3_EROFS_PREFIX:-$GK3_WORKDIR/toolchain/erofs-install}/.version" 2>/dev/null || echo unknown)"

echo '== lpmake'
LPM=$(cd "$SCRIPT_DIR/.." && pwd)/tools/otatools/bin/lpmake
LPM_SHA=ea077cf98e2178828c9376a03d5dec0cc98b59458c2a0b94cda9e59b4218467a
if [ -f "$LPM" ]; then
  # 从 Windows 提交的文件在 Linux 上可能丢掉执行位（git 不记录 filemode），这里补上
  [ -x "$LPM" ] || chmod +x "$LPM"
  got=$(sha256sum "$LPM" | cut -d' ' -f1)
  if [ "$got" = "$LPM_SHA" ]; then
    echo "  OK   $LPM（静态，sha 已固定）"
  else
    echo "  FAIL lpmake sha 不符：$got"; echo "       期望 $LPM_SHA（换工具要同时改这里与 tools/README.md）"; exit 1
  fi
else
  echo '  FAIL 缺 tools/otatools/bin/lpmake'; exit 1
fi

echo '== 内核能力'
[ -e /proc/self/ns/mnt ] && echo '  OK   mount namespace' || echo '  WARN 无 mount namespace'
echo DEPS_OK
