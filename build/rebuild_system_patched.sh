#!/usr/bin/env bash
# 重打 system.erofs（带发布清理 + OTA 补丁），产出可直接按 extent 写回 system_a 的镜像。
#
# 相对基座 parts/system.erofs 的差异（也就是白名单里的全部）：
#   1) system/bin/update_engine —— 3 字节 AVB-skip 补丁
#      （本机没有 system_other 分区/AVB 信息，EraseSystemOtherAvbFooter 必然失败；
#        legacy A/B 下这段仍在分区元数据初始化路径上，所以补丁也得留着）
#   2) system/build.prop —— 删掉 ro.virtual_ab.ublk.enabled / ro.virtual_ab.userspace.snapshots.enabled
#      （legacy A/B 不用 VABC，让引擎走老路）
#   3) system/etc/init/snapuserd.rc —— 去掉 snapuserd 的 -ublk 参数、删掉 gk3clean / gk3run 两个自用 service
#   4) system/etc/init/gk3-logdump.rc、system/etc/gk3-logdump.sh —— 整份删除（往 /metadata 灌转储的调试钩子，
#      需要时用 device/huawei/gaokun3/debug/ 里的副本加回调试版）
#
# 判据：解包基座 parts/system.erofs 得到参照树，与当前树做内容 diff，
#       差异文件必须全部落在白名单里（ALLOW 正则），否则停 —— 防止顺手带进别的东西。
#
# 安全性：只读树、只写 $HOME 与 /mnt/e 下的镜像文件，不打开任何块设备。
#
# 用法：
#   wsl -u root -d Ubuntu-24.04 -- bash /mnt/e/gk3-coloros/build/rebuild_system_patched.sh

set -euo pipefail

# 单实例锁：两次同时往 candidate.erofs 写会得到坏镜像（根 inode 被清零，
# fsck 报 "bogus i_mode (0) @ nid 128"，而 --extract 依然返回 0）
exec 9>/tmp/gk3-rebuild-system.lock
flock -n 9 || { echo "已有另一个重打在跑，退出"; exit 9; }

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
ALLOW="${ALLOW:-system/build.prop system/bin/update_engine system/etc/init/snapuserd.rc system/etc/init/gk3-logdump.rc system/etc/gk3-logdump.sh}"

for t in "$MKFS" "$FSCK"; do [ -x "$t" ] || { echo "缺工具: $t"; exit 1; }; done
[ -d "$TREE/system/bin" ] || { echo "树不存在: $TREE/system/bin"; exit 1; }
[ -f "$PARTS/system.erofs" ] || { echo "缺基座镜像: $PARTS/system.erofs"; exit 1; }

mkdir -p "$TMP"

echo "== 1. 内容判据：解包基座，与当前树比对（只允许白名单文件不同）"
if [ ! -f "$TMP/ex_base/system/bin/update_engine" ]; then
    echo "   解包基座（首次，约 1.6 GB）"
    rm -rf "$TMP/ex_base"
    "$FSCK" --extract="$TMP/ex_base" "$PARTS/system.erofs" >/dev/null
fi
diff -rq --no-dereference "$TMP/ex_base" "$TREE" > "$TMP/contentdiff.txt" 2>&1 || true
PAT=""
for f in $ALLOW; do PAT="${PAT:+$PAT|}$f"; done
UNEXPECTED=$(grep -v -E "($PAT)" "$TMP/contentdiff.txt" || true)
echo "   差异条目 $(wc -l < "$TMP/contentdiff.txt") 条："
sed 's/^/     /' "$TMP/contentdiff.txt" | head -20
if [ -n "$UNEXPECTED" ]; then
    echo "   !! 白名单外还有差异，先别写盘："
    echo "$UNEXPECTED" | sed 's/^/     /'
    exit 3
fi
echo "   通过：只有白名单文件不同"

echo "== 2. 给 update_engine 打 3 字节补丁"
python3 "$PATCH_TOOL" "$TREE/system/bin/update_engine"

echo "== 3. 检查发布清理是否真的落地"
if grep -q 'ro.virtual_ab' "$TREE/system/build.prop"; then echo "   !! build.prop 里还有 ro.virtual_ab.*"; exit 5; fi
if grep -q 'gk3run\|gk3clean' "$TREE/system/etc/init/snapuserd.rc"; then echo "   !! snapuserd.rc 里还有 gk3run / gk3clean"; exit 5; fi
if [ -e "$TREE/system/etc/init/gk3-logdump.rc" ]; then echo "   !! 调试钩子 gk3-logdump.rc 还在"; exit 5; fi
echo "   通过：无 virtual_ab 属性、无 root runner / 清理 service、无 /metadata 转储钩子"

echo "== 4. 重打 system.erofs"
rm -f "$TMP/candidate.erofs"
"$MKFS" -zlz4 -b4096 -C65536 -L system -U "$UUID_SYS" "$TMP/candidate.erofs" "$TREE" >/dev/null
SZ=$(stat -c%s "$TMP/candidate.erofs")
echo "   大小 $SZ B（分区 $LIMIT B）"
if [ "$SZ" -gt "$LIMIT" ]; then echo "   !! 超过分区大小，停。"; exit 4; fi
truncate -s "$LIMIT" "$TMP/candidate.erofs"

echo "== 5. 校验（fsck 对损坏镜像可能仍返回 0，所以必须显式检查解包结果）"
"$FSCK" "$TMP/candidate.erofs" >/dev/null 2>&1 || { echo "   !! fsck 报错，停"; exit 6; }
echo "   fsck clean"
rm -rf "$TMP/verify"
"$FSCK" --extract="$TMP/verify" "$TMP/candidate.erofs" >/dev/null 2>&1 || true
if [ ! -f "$TMP/verify/system/bin/update_engine" ]; then
    echo "   !! 解包失败/不完整（常见原因：同时跑了两次打包，镜像被写坏），重跑一次"
    exit 7
fi
echo "   镜像内 update_engine md5: $(md5sum "$TMP/verify/system/bin/update_engine" | cut -d' ' -f1)（应为 dc757f0a91d74cb340310c27fba8d564）"
echo "   镜像内 build.prop virtual_ab: $(grep -c 'ro.virtual_ab' "$TMP/verify/system/build.prop") 条（应为 0）"
echo "   镜像内 snapuserd.rc -ublk: $(grep -c 'snapuserd -ublk' "$TMP/verify/system/etc/init/snapuserd.rc") 处（应为 0）"

echo "== 6. 交给 Windows 侧"
cp "$TMP/candidate.erofs" "$OUT_WIN"
ls -l "$OUT_WIN"
sha256sum "$OUT_WIN"
echo "== 完成。接下来由主程序按 system_a 的 extent（super 内 sector 2048）原位写回。"
