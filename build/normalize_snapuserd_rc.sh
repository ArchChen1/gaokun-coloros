#!/bin/bash
# 一次性：把 snapuserd.rc 收敛到干净版
# 1) 保留 stock 两个 service，snapuserd 显式 -ublk（本机内核无 DM_USER）
# 2) 保留 init.svc.snapuserd=stopped -> snapuserd.ready=false
# 3) 删掉之前所有无效的 on boot / on property 强拉触发和 gk3diag
# 4) 加 gk3clean：开机清 /metadata 诊断转储，绝不动 /metadata/ota
set -e
rc=/home/cenmin/v50-build/system/system/etc/init/snapuserd.rc
cat > "$rc" <<'EOF'
service snapuserd /system/bin/snapuserd -ublk
    socket snapuserd stream 0660 system system
    oneshot
    disabled
    user root
    group root system
    task_profiles OtaProfiles
    seclabel u:r:snapuserd:s0

service snapuserd_proxy /system/bin/snapuserd -socket-handoff
    socket snapuserd stream 0660 system system
    socket snapuserd_proxy seqpacket 0660 system root
    oneshot
    disabled
    user root
    group root system
    seclabel u:r:snapuserd:s0

on property:init.svc.snapuserd=stopped
    setprop snapuserd.ready false

service gk3clean /system/bin/sh -c "rm -f /metadata/tombstone_* /metadata/anr_* /metadata/gk3-dmesg-*.txt /metadata/gk3-logcat-*.txt /metadata/gk3-props-*.txt /metadata/gk3-ps-*.txt /metadata/gk3-sf-*.txt /metadata/gk3-window-*.txt /metadata/gk3-*-marker; rm -rf /metadata/gk3-debug/*"
    user root
    group root system
    oneshot
    disabled

on boot
    start gk3clean
EOF
echo "--- rc written"
cat "$rc"
