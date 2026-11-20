#!/bin/bash
set -euo pipefail
I=/home/cenmin/v5/system-v25.erofs
M=/mnt/v25sys
mkdir -p "$M"
cleanup(){ umount "$M" 2>/dev/null || true; }
trap cleanup EXIT
mount -t erofs -o loop,ro "$I" "$M"
grep -n "^ro.adb.secure=" "$M/system/build.prop"
wc -l "$M/system/build.prop"
grep -E "^(ro.build.fingerprint|ro.build.version.release|ro.build.version.sdk|ro.adb.secure|ro.debuggable|ro.secure)=" "$M/system/build.prop" || true
test -f "$M/system/framework/services.jar"
test -f "$M/system/etc/init/hw/init.rc"
stat -c "%s %n" "$M/system/framework/services.jar" "$M/system/etc/init/hw/init.rc"
sha256sum "$I"
echo SYSTEM_V25_CHECK_OK
