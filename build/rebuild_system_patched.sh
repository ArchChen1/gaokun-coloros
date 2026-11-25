#!/usr/bin/env bash
# 重打 system.erofs：给 /system/bin/update_engine 打 3 字节 AVB-skip 补丁后再打包。
#
# 为什么要打：本机没有 system_other 分区/AVB 信息，update_engine 在
# EraseSystemOtherAvbFooter() 必然失败，OTA 连下载阶段都过不去（kInstallDeviceOpenError 7）。
# 补丁把该函数入口的判断改成无条件成功，详见 tools/ota/patch_update_engine_avb.py。
#
# 安全性：只读解包树、写 $HOME 与 /mnt/e 下的镜像文件，不打开任何块设备。
#
# 用法（WSL，root 或普通用户都行；树是 root 所有的，用 root 更稳）：
#   wsl -u root -d Ubuntu-24.04 -- bash /mnt/e/gk3-coloros/work/rebuild_system_patched.sh

set -euo pipefail

TREE=/home/cenmin/v50-build/system            # 里面有 system/ 子目录，就是 mkfs 的目标根
PARTS=/home/cenmin/coloros-build/current/parts
MKFS=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
PATCH_TOOL=/mnt/e/gk3-coloros/tools/ota/patch_update_engine_avb.py
TMP=/home/cenmin/sys_rebuild
OUT_WIN=/mnt/e/gk3-coloros/work/system_patched.erofs
LIMIT=1137397760                               # system_a：2,221,480 sectors
# 与 build/current_build.sh 一致（基座 parts/system.erofs 是早期随机 UUID 的版本，
# 两者内容已比对为 0 差异，UUID 只影响超级块字节，不影响挂载）
UUID_SYS=4f3a1b2c-5d6e-4f70-8a91-b2c3d4e5f601
SB_END=1280                                    # 超级块区（1024..1280）内允许有差异

for t in "$MKFS" "$FSCK"; do [ -x "$t" ] || { echo "缺工具: $t"; exit 1; }; done
[ -d "$TREE/system/bin" ] || { echo "树不存在: $TREE/system/bin"; exit 1; }
[ -f "$PARTS/system.erofs" ] || { echo "缺基座镜像: $PARTS/system.erofs"; exit 1; }

mkdir -p "$TMP"

echo "== 1. 金丝雀：用当前树原样重打，与基座比对（只允许超级块内差异）"
"$MKFS" -zlz4 -b4096 -C65536 -L system -U "$UUID_SYS" "$TMP/canary.erofs" "$TREE" >/dev/null
echo "   重打: $(stat -c%s "$TMP/canary.erofs") B  基座: $(stat -c%s "$PARTS/system.erofs") B"
# 用 cmp -l 列出所有不同字节；超级块里的 build_time/checksum 必然不同（每次打包写当前时间）
cmp -l "$TMP/canary.erofs" "$PARTS/system.erofs" > "$TMP/cmp.txt" || true
BAD=$(awk -v lim="$SB_END" '$1 > lim' "$TMP/cmp.txt" | wc -l)
echo "   不同字节 $(wc -l < "$TMP/cmp.txt") 个，其中超级块之外 $BAD 个"
if [ "$BAD" -ne 0 ]; then
    echo "   !! 超级块之外有差异（树相对基座内容漂移），先别写盘。样本："
    awk -v lim="$SB_END" '$1 > lim' "$TMP/cmp.txt" | head -10
    exit 3
fi
echo "   通过：树内容与基座一致，仅超级块时间戳不同"

echo "== 2. 给 update_engine 打 3 字节补丁"
python3 "$PATCH_TOOL" "$TREE/system/bin/update_engine"

echo "== 3. 重打 system.erofs"
"$MKFS" -zlz4 -b4096 -C65536 -L system -U "$UUID_SYS" "$TMP/candidate.erofs" "$TREE" >/dev/null
SZ=$(stat -c%s "$TMP/candidate.erofs")
echo "   大小 $SZ B（分区 $LIMIT B）"
if [ "$SZ" -gt "$LIMIT" ]; then echo "   !! 超过分区大小，停。"; exit 4; fi
truncate -s "$LIMIT" "$TMP/candidate.erofs"

echo "== 4. 校验"
"$FSCK" "$TMP/candidate.erofs" >/dev/null && echo "   fsck clean"
rm -rf "$TMP/verify"
"$FSCK" --extract="$TMP/verify" "$TMP/candidate.erofs" >/dev/null
echo "   镜像内 update_engine md5: $(md5sum "$TMP/verify/system/bin/update_engine" | cut -d' ' -f1)（应为 dc757f0a91d74cb340310c27fba8d564）"
echo "   镜像内 otacerts.zip  sha: $(sha256sum "$TMP/verify/system/etc/security/otacerts.zip" 2>/dev/null | cut -d' ' -f1)"

echo "== 5. 交给 Windows 侧"
cp "$TMP/candidate.erofs" "$OUT_WIN"
ls -l "$OUT_WIN"
sha256sum "$OUT_WIN"
echo "== 完成。接下来由主程序按 system_a 的 extent（super 内 sector 2048）原位写回。"
