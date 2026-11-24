#!/usr/bin/env bash
# doctor：检查 WSL 侧工具与 llvm-mingw
set -uo pipefail
for t in mkfs.erofs fsck.erofs simg2img zstd make clang python3 curl getfattr e2fsck; do
  if command -v "$t" >/dev/null 2>&1; then printf '  OK   %-12s %s\n' "$t" "$(command -v "$t")"; else printf '  FAIL %-12s 未安装\n' "$t"; fi
done
ver=$(mkfs.erofs 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
echo "  mkfs.erofs 版本: ${ver:-unknown}"

Llm=${GK3_LLVM_MINGW:-llvm-mingw-20261104-ucrt-ubuntu-22.04-x86_64}
if [ -d "$HOME/opt/$Llm" ]; then echo "  OK   llvm-mingw ($Llm)"; else echo "  MISS llvm-mingw（安装器后端需要，build.ps1 会自动下载）"; fi
[ -x /mnt/e/gk3-coloros/tools/otatools/bin/lpmake ] && echo '  OK   lpmake' || echo '  WARN lpmake 不在仓库 tools/otatools/bin'
