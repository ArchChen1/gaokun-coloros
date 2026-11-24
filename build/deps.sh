#!/usr/bin/env bash
# 安装构建依赖（Debian/Ubuntu，WSL 亦可）。只做检查与安装，不改动系统其它配置。
set -euo pipefail
SUDO=${SUDO:-sudo}

need_pkgs="python3 python3-pip curl git zstd e2fsprogs attr android-sdk-libsparse-utils clang"
need_pkgs="$need_pkgs erofs-utils util-linux"

if ! command -v apt-get >/dev/null; then
  echo "非 Debian/Ubuntu：请自行安装 $need_pkgs 以及 erofs-utils(>=1.9)" >&2
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

echo '== 工具检查'
for t in mkfs.erofs fsck.erofs simg2img zstd python3; do
  if command -v "$t" >/dev/null; then printf '  OK   %-12s %s\n' "$t" "$(command -v "$t")"; else printf '  FAIL %s 未找到\n' "$t"; exit 1; fi
done

ver=$(mkfs.erofs 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
echo "  mkfs.erofs 版本: ${ver:-unknown}"
case "$ver" in
  1.9.*|1.1[0-9].*|2.*) ;;
  *) echo '  警告：mkfs.erofs 建议 >= 1.9，否则 erofs 校验/兼容可能有差异' ;;
esac

echo '== lpmake'
LPM=$(cd "$(dirname "$0")/.." && pwd)/tools/otatools/bin/lpmake
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
