#!/bin/bash
set -euo pipefail
B=/home/cenmin/coloros-build
R=/tmp/system-extract
echo '===== ODM VINTF FILES ====='
find "$B/vendor-tree/odm" -maxdepth 6 -type f \( -name '*manifest*.xml' -o -name '*compatibility*.xml' -o -name 'manifest.xml' \) -printf '%p %s\n' 2>/dev/null | sort | head -200
echo '===== ODM VINTF DIRS ====='
find "$B/vendor-tree/odm" -maxdepth 5 -type d -path '*vintf*' -printf '%p\n' 2>/dev/null | sort
echo '===== ODM KEYSTORE/KEYMINT FILES ====='
find "$B/vendor-tree/odm" -maxdepth 7 -type f \( -iname '*keymint*' -o -iname '*keystore*' -o -iname '*security*' \) -printf '%p %s\n' 2>/dev/null | sort | head -200
echo '===== VENDOR KEYSTORE/KEYMINT FILES ====='
find "$B/vendor-tree" -maxdepth 6 -type f \( -iname '*keymint*' -o -iname '*keystore*' \) -not -path '*/odm/*' -printf '%p %s\n' 2>/dev/null | sort | head -200
echo '===== SYSTEM KEYSTORE/KEYMINT FILES ====='
find "$R" -maxdepth 6 -type f \( -iname '*keymint*' -o -iname '*keystore*' \) -printf '%p %s\n' 2>/dev/null | sort | head -200