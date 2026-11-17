#!/usr/bin/env bash
set -euo pipefail
for f in \
/home/cenmin/coloros-trees-xattr/system/system/build.prop \
/home/cenmin/coloros-trees-xattr/system_ext/etc/build.prop \
/home/cenmin/coloros-trees-xattr/product/etc/build.prop \
/home/cenmin/coloros-trees-xattr/vendor/build.prop \
/home/cenmin/coloros-trees-xattr/odm/etc/build.prop \
/home/cenmin/coloros-trees-xattr/my_product/etc/build.prop \
/home/cenmin/coloros-trees-xattr/my_manifest/build.prop; do
  echo "==== $f"
  if [ -f "$f" ]; then
    grep -E '^(ro\.product\.(device|name|model)|ro\.board\.platform|ro\.build\.version\.(sdk|release)|ro\.hardware)' "$f" | head -20 || true
  else
    echo missing
  fi
done
