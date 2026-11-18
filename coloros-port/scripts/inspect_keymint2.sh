#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
echo '===== KEYMINT RC ====='
cat /tmp/system-extract/system/etc/init/keystore2.rc
echo '===== KEYMINT APEX CONTENT ====='
rm -rf /tmp/keymint-apex
mkdir -p /tmp/keymint-apex
cd /tmp/keymint-apex
unzip -l "$B/vendor-tree/apex/com.android.hardware.keymint.rust_nonsecure.apex" | head -100
echo '===== ODM TOP ====='
find "$B/vendor-tree/odm" -maxdepth 3 -printf '%y %p\n' 2>/dev/null | sort | head -160
echo '===== ODM ETC ====='
find "$B/vendor-tree/odm/etc" -maxdepth 4 -type f -printf '%p %s\n' 2>/dev/null | sort | head -200