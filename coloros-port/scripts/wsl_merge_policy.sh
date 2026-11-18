#!/bin/bash
set -euo pipefail
ORIGINAL_CIL=${ORIGINAL_CIL:-/home/cenmin/policywork/coloros-odm-policy.cil}
GAOKUN_VERSIONED_CIL=${GAOKUN_VERSIONED_CIL:-/home/cenmin/coloros-build/policy-src/gaokun_vendor/plat_pub_versioned.cil}
GAOKUN_VENDOR_CIL=${GAOKUN_VENDOR_CIL:-/home/cenmin/coloros-build/policy-src/gaokun_vendor/vendor_sepolicy.cil}
OUTPUT=${OUTPUT:-/home/cenmin/policywork/precompiled_sepolicy.merged}
SECILC=${SECILC:-/home/cenmin/toolchain/secilc/secilc}
CHECKPOLICY=${CHECKPOLICY:-/home/cenmin/toolchain/checkpolicy/checkpolicy}
DUMP=${DUMP:-${OUTPUT}.cil}
for f in "$ORIGINAL_CIL" "$GAOKUN_VERSIONED_CIL" "$GAOKUN_VENDOR_CIL"; do
  [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
LD_LIBRARY_PATH=/lib "$SECILC" -N -m -M true -G -c 35 -f /dev/null -o "$OUTPUT" \
  "$ORIGINAL_CIL" "$GAOKUN_VERSIONED_CIL" "$GAOKUN_VENDOR_CIL"
LD_LIBRARY_PATH=/lib "$CHECKPOLICY" -b -M -C -o "$DUMP" "$OUTPUT"
types=$(grep -c '^(type ' "$DUMP")
allows=$(grep -c '^ *(allow ' "$DUMP")
[ "$types" -ge 4760 ]
[ "$allows" -ge 125000 ]
echo "types=$types allows=$allows"
sha256sum "$OUTPUT"
stat -c '%s %n' "$OUTPUT"
