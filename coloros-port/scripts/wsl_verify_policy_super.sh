#!/bin/bash
set -euo pipefail

ROOT=${ROOT:-/home/cenmin/coloros-build}
SUPER_A=${SUPER_A:-$ROOT/super-coloros-a.img}
SUPER_C=${SUPER_C:-$ROOT/super-coloros-c-merged.img}
POLICY=${POLICY:-/home/cenmin/policywork/precompiled_sepolicy.merged}
SCRIPTS=${SCRIPTS:-/mnt/e/gaokun-coloros/coloros-port/scripts}
CHECK=${CHECK:-$ROOT/verify-policy-super-c}
FSCK_EROFS=${FSCK_EROFS:-/home/cenmin/toolchain/erofs-install/bin/fsck.erofs}
EXPECTED_POLICY_SHA=${EXPECTED_POLICY_SHA:-3fb220b5ee9f0edb132b760c2c2ca54b597a1a05a2d3f03ca28885d12ef70288}

for f in "$SUPER_A" "$SUPER_C" "$POLICY"; do
  [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
rm -rf "$CHECK"
mkdir -p "$CHECK/a" "$CHECK/c" "$CHECK/mnt"

for part in system_a vendor_a; do
  python3 "$SCRIPTS/partition_inspect.py" "$SUPER_A" --extract "$part" "$CHECK/a/${part}.img" >/dev/null
  python3 "$SCRIPTS/partition_inspect.py" "$SUPER_C" --extract "$part" "$CHECK/c/${part}.img" >/dev/null
done
python3 "$SCRIPTS/partition_inspect.py" "$SUPER_C" --extract odm_a "$CHECK/c/odm_a.img" >/dev/null

cmp -s "$CHECK/a/system_a.img" "$CHECK/c/system_a.img"
cmp -s "$CHECK/a/vendor_a.img" "$CHECK/c/vendor_a.img"
"$FSCK_EROFS" "$CHECK/c/odm_a.img" >/dev/null

mount -t erofs -o loop,ro "$CHECK/c/odm_a.img" "$CHECK/mnt"
trap 'umount "$CHECK/mnt" 2>/dev/null || true' EXIT
actual=$(sha256sum "$CHECK/mnt/etc/selinux/precompiled_sepolicy" | cut -d' ' -f1)
[ "$actual" = "$EXPECTED_POLICY_SHA" ]
[ "$actual" = "$(sha256sum "$POLICY" | cut -d' ' -f1)" ]
[ "$(getfattr --only-values -n security.selinux "$CHECK/mnt/etc/selinux/precompiled_sepolicy" 2>/dev/null)" = "u:object_r:sepolicy_file:s0" ]
echo "policy-super verification passed"
echo "odm_sha256=$(sha256sum "$CHECK/c/odm_a.img" | cut -d' ' -f1)"
echo "policy_sha256=$actual"
