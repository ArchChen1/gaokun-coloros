#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
echo '===== ORIGINAL ODM SOURCE LOCATIONS ====='
find "$B" -maxdepth 4 -type f \( -name 'odm.img' -o -name '*odm*.img' -o -name '*odm*.raw' -o -name '*odm*.simg' \) -printf '%p %s\n' 2>/dev/null | sort
echo '===== ONEplus extracted ODM ====='
find /mnt/e/gaokun-coloros/analysis -maxdepth 6 -type f \( -name 'odm.img' -o -name '*odm*.img' \) -printf '%p %s\n' 2>/dev/null | head -100