#!/bin/bash
# 一次性：给 build.prop 补 ro.virtual_ab.userspace.snapshots.enabled=true
# 依据：snapuserd 启动时打印 "Userspace snapshots not enabled. No support for legacy snapshots" 后退出 1
set -e
f=/home/cenmin/v50-build/system/system/build.prop
if grep -q '^ro.virtual_ab.userspace.snapshots.enabled=true$' "$f"; then
    echo "already set"
else
    sed -i '/^ro.virtual_ab.ublk.enabled=true/a ro.virtual_ab.userspace.snapshots.enabled=true' "$f"
    echo "added"
fi
grep -n 'virtual_ab' "$f"
