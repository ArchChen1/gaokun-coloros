#!/bin/bash
# 一次性：在 snapuserd.rc 里加 gk3run —— 按需 root runner
# 用法：adb shell "写入 /data/local/tmp/gk3run.sh" 然后 adb shell setprop ctl.start gk3run
# 发布前必须删除本服务（见 docs/OTA-VABC-UBLK.md 的发布清单）
set -e
rc=/home/cenmin/v50-build/system/system/etc/init/snapuserd.rc
if grep -q 'service gk3run' "$rc"; then
    echo "already present"
    exit 0
fi
cat >> "$rc" <<'EOF'

service gk3run /system/bin/sh /data/local/tmp/gk3run.sh
    user root
    group root system
    oneshot
    disabled
EOF
echo "added"
tail -6 "$rc"
