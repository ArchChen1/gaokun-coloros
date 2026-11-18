#!/bin/bash
set -euo pipefail

SOURCE_IMG=${SOURCE_IMG:-/mnt/e/gaokun-coloros/coloros-port/work/opd2513/odm.img}
POLICY_BIN=${POLICY_BIN:-/home/cenmin/policywork/precompiled_sepolicy.merged}
WORK=${WORK:-/home/cenmin/odm-work}
OUTPUT=${OUTPUT:-/home/cenmin/odm-final.raw.img}
MKFS_EROFS=${MKFS_EROFS:-/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs}
FSCK_EROFS=${FSCK_EROFS:-/home/cenmin/toolchain/erofs-install/bin/fsck.erofs}

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root" >&2
  exit 1
fi
case "$WORK" in
  /home/cenmin/*) ;;
  *) echo "unsafe WORK path: $WORK" >&2; exit 1 ;;
esac

for f in "$SOURCE_IMG" "$POLICY_BIN"; do
  [ -f "$f" ] || { echo "missing input: $f" >&2; exit 1; }
done
for t in "$MKFS_EROFS" "$FSCK_EROFS"; do
  [ -x "$t" ] || { echo "missing tool: $t" >&2; exit 1; }
done

MOUNT_POINT="$WORK/source"
POLICY_ROOT="$WORK/policy-root"
ARCHIVE="$WORK/odm-patched.tar"
mkdir -p "$WORK" "$MOUNT_POINT" "$POLICY_ROOT/etc/selinux"
umount "$MOUNT_POINT" 2>/dev/null || true
mount -t erofs -o loop,ro "$SOURCE_IMG" "$MOUNT_POINT"
cleanup() { umount "$MOUNT_POINT" 2>/dev/null || true; }
trap cleanup EXIT

cp "$POLICY_BIN" "$POLICY_ROOT/etc/selinux/precompiled_sepolicy"
chmod 644 "$POLICY_ROOT/etc/selinux/precompiled_sepolicy"
setfattr -n security.selinux -v 'u:object_r:sepolicy_file:s0' "$POLICY_ROOT/etc/selinux/precompiled_sepolicy"

cd "$MOUNT_POINT"
tar --format=gnu --xattrs --xattrs-include='*' --numeric-owner \
  -cf "$ARCHIVE" --exclude='./etc/selinux/precompiled_sepolicy' .
tar --format=gnu --xattrs --xattrs-include='*' --numeric-owner \
  -rf "$ARCHIVE" -C "$POLICY_ROOT" ./etc/selinux/precompiled_sepolicy

entries=$(tar -tf "$ARCHIVE" | wc -l)
if [ "$entries" -lt 2900 ]; then
  echo "tar looks incomplete: $entries entries" >&2
  exit 1
fi

cat "$ARCHIVE" | "$MKFS_EROFS" --tar=f -zlz4 -b4096 -C1048576 \
  -L odm -T1793346620 -U2f2ea3d1-c76b-5f2c-b99b-45ba6421cc21 \
  "$OUTPUT"
"$FSCK_EROFS" "$OUTPUT"

CHECK_MOUNT="$WORK/check"
mkdir -p "$CHECK_MOUNT"
mount -t erofs -o loop,ro "$OUTPUT" "$CHECK_MOUNT"
test "$(sha256sum "$CHECK_MOUNT/etc/selinux/precompiled_sepolicy" | cut -d' ' -f1)" = \
     "$(sha256sum "$POLICY_BIN" | cut -d' ' -f1)"
test "$(getfattr --only-values -n security.selinux "$CHECK_MOUNT/etc/selinux/precompiled_sepolicy" 2>/dev/null)" = \
     "u:object_r:sepolicy_file:s0"
umount "$CHECK_MOUNT"

sha256sum "$OUTPUT"
stat -c '%s %n' "$OUTPUT"
