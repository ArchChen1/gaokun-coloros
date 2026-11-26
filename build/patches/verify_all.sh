#!/bin/bash
# 一条命令查出「补丁有没有丢」。出包、出 payload、发版前都跑这个。
#
#   bash build/patches/verify_all.sh [manifest.json]
#
# 检查五层：
#   1) 账本自证：13 个分区 path/bytes/sha256 与 manifest 完全一致
#   2) 关键 sha 钉死：system / vendor / my_engineering 必须等于设备实证值
#   3) 补丁内容在位：挂载 vendor / my_engineering，直接看补丁文件本身
#   4) 反向检查：产物里不该出现的东西（旧 system、未打补丁的 C2 rc、原厂 otacerts）
#   5) 内核/引导：内核树 git HEAD + config sha + vmlinuz.efi sha + ESP 三件套
#      （内核补丁不在分区账本里，单靠这一层兜。SKIP_KERNEL=1 可跳过）
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
MAN=${1:-/home/cenmin/coloros-build/current/manifest.json}
STATE=$(dirname "$MAN")
FAIL=0

say() { printf '%s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*"; FAIL=1; }
ok() { printf '  OK   %s\n' "$*"; }

say "== 1. 账本自证"
python3 "$ROOT/tools/ota/parts_manifest.py" verify --manifest "$MAN" || FAIL=1

say "== 2. 关键分区 sha 钉死（设备实证值）"
declare -A PIN=(
  [system]=a4b91f7305641b51c993f625063be8074b81674953242a721d1b7cc1fe2ed22e
  [vendor]=dd574c1756496e2fdf598748600da5229862fdef3a1bc8a591a5685f08c0defb
  [my_engineering]=ce71e4b632eac3f65ccb5bbfaddad0ba9721ffa1511a88a729637c34baa7e6bb
)
for n in "${!PIN[@]}"; do
    p=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['parts']['$n']['sha256'])" "$MAN")
    if [ "$p" = "${PIN[$n]}" ]; then ok "$n = ${p:0:16}…"; else fail "$n = ${p:0:16}…（应为 ${PIN[$n]:0:16}…）"; fi
done

say "== 3. 补丁内容在位"
V=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['parts']['vendor']['path'])" "$MAN")
E=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['parts']['my_engineering']['path'])" "$MAN")
S=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['parts']['system']['path'])" "$MAN")
T=$(mktemp -d); trap 'umount "$T/v" 2>/dev/null; umount "$T/e" 2>/dev/null; umount "$T/s" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/v" "$T/e" "$T/s"
if mount -o loop,ro "$S" "$T/s"; then
    if grep -q 'ro\.virtual_ab' "$T/s/system/build.prop" 2>/dev/null; then fail "system：build.prop 还有 ro.virtual_ab.*（VABC 属性没清）"; fi
    if [ -e "$T/s/system/etc/init/gk3-logdump.rc" ]; then fail "system：调试钩子 gk3-logdump.rc 还在"; fi
    if grep -q 'gk3run\|gk3clean' "$T/s/system/etc/init/snapuserd.rc" 2>/dev/null; then fail "system：snapuserd.rc 里还有 gk3run / gk3clean（root runner 没撤）"; fi
    if grep -q 'snapuserd -ublk' "$T/s/system/etc/init/snapuserd.rc" 2>/dev/null; then fail "system：snapuserd 还带 -ublk"; fi
    if [ -f "$T/s/system/priv-app/OtaUpdater/OtaUpdater.apk" ] && [ -x "$T/s/system/bin/gk3otad.sh" ] && [ -f "$T/s/system/etc/init/gk3otad.rc" ]; then
        U=$(sha256sum "$T/s/system/priv-app/OtaUpdater/OtaUpdater.apk" | cut -d' ' -f1)
        ok "system：更新器已预装 + 写入服务在位（apk ${U:0:12}…）"
    else fail "system：更新器 / 写入服务没预装进镜像"; fi
    ok "system：发布清理在位（无 virtual_ab / 无 logdump / 无 root runner / 无 -ublk）"
else fail "system 镜像挂不上：$S"; fi
if mount -o loop,ro "$V" "$T/v"; then
    RC="$T/v/etc/init/android.hardware.media.c2-service-v4l2.rc"
    if grep -q 'interface aidl android.hardware.media.c2.IComponentStore/default' "$RC" 2>/dev/null; then
        ok "vendor：C2 HAL 已声明 AIDL 接口（会被 init 拉起）"
    else fail "vendor：C2 rc 里没有 interface aidl 声明（C2 补丁丢了）"; fi
    if grep -q '^\s*disabled\s*$' "$RC" 2>/dev/null; then fail "vendor：C2 rc 仍是 disabled"; fi
else fail "vendor 镜像挂不上：$V"; fi
if mount -o loop,ro "$E" "$T/e"; then
    Z="$T/e/etc/security/otacerts.zip"
    got=$(sha256sum "$Z" 2>/dev/null | cut -d' ' -f1)
    if [ "$got" = e98d97cb883e7bfa857443e3119070c162d15c721829a158b2c7a9314aef42a8 ]; then
        ok "my_engineering：otacerts.zip = 自签证书"
    else fail "my_engineering：otacerts.zip 是 ${got:0:16}…（不是自签，OTA 验签会失败）"; fi
else fail "my_engineering 镜像挂不上：$E"; fi

say "== 4. 反向检查"
case "$V" in
  */vendor.img.pre_c2) fail "vendor 指向了 pre_c2（未打 C2 补丁）";;
  *) ok "vendor 不是 pre_c2";;
esac

say "== 5. 内核 / 引导三件套"
if [ "${SKIP_KERNEL:-0}" = 1 ]; then
    say "  --   SKIP_KERNEL=1，跳过"
elif [ -d "$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['kernel']['tree'])" "$ROOT/patches/kernel-build/kernel-artifact.json" 2>/dev/null)" ]; then
    bash "$HERE/verify_kernel.sh" || FAIL=1
else
    say "  --   内核树不在本机（另一台机器？），跳过第 5 层；发布机器上必须跑"
fi

say ""
if [ "$FAIL" = 0 ]; then say "VERIFY_ALL_PASSED"; exit 0; fi
say "VERIFY_ALL_FAILED"; exit 1
