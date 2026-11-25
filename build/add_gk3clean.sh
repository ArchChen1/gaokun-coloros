#!/bin/bash
# 一次性：在 snapuserd.rc 里加开机清理服务 gk3clean
# 只清诊断转储/tombstone，绝不触碰 /metadata/ota（OTA 状态）
set -e
rc=/home/cenmin/v50-build/system/system/etc/init/snapuserd.rc
if grep -q 'service gk3clean' "$rc"; then
    echo "already present"
    tail -8 "$rc"
    exit 0
fi
cat >> "$rc" <<'EOF'

service gk3clean /system/bin/sh -c "rm -f /metadata/tombstone_* /metadata/anr_* /metadata/gk3-dmesg-*.txt /metadata/gk3-logcat-*.txt /metadata/gk3-props-*.txt /metadata/gk3-ps-*.txt /metadata/gk3-sf-*.txt /metadata/gk3-window-*.txt /metadata/gk3-*-marker; rm -rf /metadata/gk3-debug/*"
    user root
    group root system
    oneshot
    disabled

on boot
    start gk3clean
EOF
echo "added"
tail -10 "$rc"
