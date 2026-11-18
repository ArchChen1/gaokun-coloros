#!/bin/bash
set -euo pipefail
ORIGINAL=${ORIGINAL:-/home/cenmin/coloros-build/policy-src/odm/precompiled_sepolicy}
CIL=${CIL:-/home/cenmin/policywork/coloros-odm-policy.cil}
CHECKPOLICY=${CHECKPOLICY:-/home/cenmin/toolchain/checkpolicy/checkpolicy}
[ -f "$ORIGINAL" ] || { echo "missing: $ORIGINAL" >&2; exit 1; }
[ -x "$CHECKPOLICY" ] || { echo "missing: $CHECKPOLICY" >&2; exit 1; }
LD_LIBRARY_PATH=/lib "$CHECKPOLICY" -b -M -C -o "$CIL" "$ORIGINAL"
types=$(grep -c '^(type ' "$CIL")
allows=$(grep -c '^ *(allow ' "$CIL")
[ "$types" -ge 4600 ]
[ "$allows" -ge 120000 ]
echo "types=$types allows=$allows"
sha256sum "$CIL"
