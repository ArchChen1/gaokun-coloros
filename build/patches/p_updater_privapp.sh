#!/usr/bin/env bash
# 补丁：把 com.oplus.ota（更新器 UI）和 gk3otad（写入服务）预装进 system 树。
#
# 依据：docs/OTA-ONLINE-PLAN.md 第 7 节 —— Settings 的「软件更新」一行只认
# 包名 com.oplus.ota + 声明 com.oplus.ota.MAIN 的 Activity，所以只要包预装，
# 那一行就会自己出现，不用改 Settings。
#
# 用法：bash build/patches/p_updater_privapp.sh
#   APK=$REPO/work/updater-build/gk3-ota.apk（由 build/updater_build.ps1 产出）
#   目标树 = /home/cenmin/v50-build/system

set -euo pipefail

TREE=${TREE:-/home/cenmin/v50-build/system}
REPO=${REPO:-/mnt/e/gk3-coloros}
APK="$REPO/work/updater-build/gk3-ota.apk"

[ -f "$APK" ] || { echo "缺 APK：$APK（先跑 build/updater_build.ps1）"; exit 1; }
[ -d "$TREE/system/priv-app" ] || { echo "目标树不对：$TREE"; exit 1; }

DST_APK="$TREE/system/priv-app/OtaUpdater/OtaUpdater.apk"
DST_SH="$TREE/system/bin/gk3otad.sh"
DST_RC="$TREE/system/etc/init/gk3otad.rc"

install -D -m 0644 "$APK" "$DST_APK"
install -D -m 0755 "$REPO/updater/system/gk3otad.sh" "$DST_SH"
install -D -m 0644 "$REPO/updater/system/gk3otad.rc" "$DST_RC"

echo "已预装："
ls -l "$DST_APK" "$DST_SH" "$DST_RC"
echo "APK sha256：$(sha256sum "$DST_APK" | cut -d' ' -f1)"
