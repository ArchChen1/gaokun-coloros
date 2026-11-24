#!/usr/bin/env bash
# 全局配置入口。所有 build/*.sh 都 source 这里，禁止在脚本里写死本机路径。
#
# 布局（默认）：
#   $GK3_WORKDIR/
#   ├── in/            外部输入：vendor_base.img、my_product.erofs、my_stock.erofs、src/
#   ├── trees/         解包后的 system/ 与 odm/ 树（改补丁就在这里改）
#   ├── current/       基座产物 parts/、manifest.json、release/、logs/
#   └── toolchain/     可选的本地 erofs-utils

: "${GK3_WORKDIR:=$HOME/gk3-build}"

# 机器级覆盖文件，按顺序找第一个存在的：
#   $GK3_ENV_FILE → $HOME/.config/gk3-coloros/env → /home/$SUDO_USER/.config/gk3-coloros/env
for f in "${GK3_ENV_FILE:-}" "$HOME/.config/gk3-coloros/env" \
         "${SUDO_USER:+/home/$SUDO_USER/.config/gk3-coloros/env}"; do
  if [ -n "$f" ] && [ -f "$f" ]; then
    # shellcheck disable=SC1090
    . "$f"
    break
  fi
done

: "${GK3_STATE:=$GK3_WORKDIR/current}"
: "${GK3_TREES:=$GK3_WORKDIR/trees}"
: "${GK3_INPUTS:=$GK3_WORKDIR/in}"
: "${GK3_SRC:=$GK3_INPUTS/src}"
: "${GK3_PUBLISH:=/mnt/d/gaokun-coloros-release/latest}"

GK3_PARTS="$GK3_STATE/parts"
GK3_SYS_TREE="$GK3_TREES/system"          # mkfs 的目标根（其下有 system/ 子目录）
GK3_SYS="$GK3_SYS_TREE/system"            # 断言用的 system 文件树
GK3_ODM="$GK3_TREES/odm"
GK3_VENDOR_BASE="$GK3_INPUTS/vendor_base.img"
GK3_MY_PRODUCT="$GK3_INPUTS/my_product.erofs"
GK3_MY_STOCK="$GK3_INPUTS/my_stock.erofs"

# erofs 工具：优先用 build/erofs_build.sh 装在 toolchain/ 下的钉版（1.9.4），
# 保证不同机器（含 CI）产出同样的分区镜像；机器级配置里显式指定则以配置为准。
_erofs_prefix="${GK3_EROFS_PREFIX:-$GK3_WORKDIR/toolchain/erofs-install}"
if [ -x "$_erofs_prefix/bin/mkfs.erofs" ] && [ -x "$_erofs_prefix/bin/fsck.erofs" ]; then
  : "${GK3_MKFS_EROFS:=$_erofs_prefix/bin/mkfs.erofs}"
  : "${GK3_FSCK_EROFS:=$_erofs_prefix/bin/fsck.erofs}"
fi
GK3_MKFS_EROFS="${GK3_MKFS_EROFS:-mkfs.erofs}"
GK3_FSCK_EROFS="${GK3_FSCK_EROFS:-fsck.erofs}"
GK3_OTATOOLS="${GK3_OTATOOLS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tools/otatools/bin}"

export GK3_WORKDIR GK3_STATE GK3_PARTS GK3_TREES GK3_SYS_TREE GK3_SYS GK3_ODM \
       GK3_INPUTS GK3_SRC GK3_PUBLISH GK3_VENDOR_BASE GK3_MY_PRODUCT GK3_MY_STOCK \
       GK3_MKFS_EROFS GK3_FSCK_EROFS GK3_OTATOOLS
