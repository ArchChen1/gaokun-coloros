#!/bin/bash
set -euo pipefail

SRC=/home/cenmin/v5/parts/odm_a.img
OUT=/home/cenmin/v5/parts/odm_v23_a.img
WORK=/home/cenmin/v23-work
MKFS=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
PATCH=/mnt/e/gaokun-coloros/coloros-port/scripts/v23_patch_odm_audio.py
MOUNT="$WORK/src"

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root" >&2
  exit 1
fi
for f in "$SRC" "$PATCH"; do
  [ -e "$f" ] || { echo "missing $f" >&2; exit 1; }
done
for t in "$MKFS" "$FSCK"; do
  [ -x "$t" ] || { echo "missing $t" >&2; exit 1; }
done

rm -rf "$WORK"
mkdir -p "$WORK/extract" "$MOUNT"
mount -t erofs -o loop,ro "$SRC" "$MOUNT"
cleanup() { umount "$MOUNT" 2>/dev/null || true; }
trap cleanup EXIT

cp -a "$MOUNT/." "$WORK/extract/"
cp -a "$MOUNT/etc/selinux/precompiled_sepolicy" "$WORK/precompiled_sepolicy.orig"
umount "$MOUNT"

python3 "$PATCH" "$WORK/extract"
stat -c "policy mode=%a uid=%u gid=%g size=%s" "$WORK/extract/etc/audio/audio_policy_configuration.xml"
if grep -q '<module name="binaural_record"' "$WORK/extract/etc/audio/audio_policy_configuration.xml"; then
  echo "binaural_record remains in extracted policy" >&2
  exit 2
fi

rm -f "$OUT"
"$MKFS" -zlz4 -b4096 -C1048576 -L odm -T1793346620                 -U2f2ea3d1-c76b-5f2c-b99b-45ba6421cc21 "$OUT" "$WORK/extract"
"$FSCK" "$OUT"

CHECK="$WORK/check"
mkdir -p "$CHECK"
mount -t erofs -o loop,ro "$OUT" "$CHECK"
if grep -q '<module name="binaural_record"' "$CHECK/etc/audio/audio_policy_configuration.xml"; then
  echo "binaural_record remains in rebuilt ODM" >&2
  exit 3
fi
cmp -s "$CHECK/etc/selinux/precompiled_sepolicy" "$WORK/precompiled_sepolicy.orig" || {
  echo "sepolicy changed unexpectedly" >&2
  exit 4
}
getfattr --only-values -n security.selinux "$CHECK/etc/audio/audio_policy_configuration.xml" 2>/dev/null || true
echo "ODM_V23_OK"
umount "$CHECK"
sha256sum "$OUT"
stat -c "%s %n" "$OUT"

