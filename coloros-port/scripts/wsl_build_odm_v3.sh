#!/bin/bash
set -euo pipefail
SRC=/home/cenmin/odm-final-vintffix.raw.img
POLICY=/home/cenmin/policywork/precompiled_sepolicy.merged
WORK=/home/cenmin/odm-v3-work
OUT=/home/cenmin/odm-final-v3.raw.img
MKFS=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FSCK=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
if [ "$(id -u)" -ne 0 ]; then echo 'run as root' >&2; exit 1; fi
for f in "$SRC" "$POLICY"; do [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }; done
for t in "$MKFS" "$FSCK"; do [ -x "$t" ] || { echo "missing $t" >&2; exit 1; }; done
rm -rf "$WORK"
mkdir -p "$WORK/src" "$WORK/overlay" "$WORK/policy/etc/selinux"
mount -t erofs -o loop,ro "$SRC" "$WORK/src"
cleanup(){ umount "$WORK/src" 2>/dev/null || true; }
trap cleanup EXIT

FILES=(
  'etc/init/init.touchDaemon.rc'
  'etc/init/vendor.oplus.hardware.biometrics.face@1.0-service.rc'
  'etc/init/vendor.oplus.hardware.biometrics.fingerprintpay@1.0-service.rc'
  'etc/init/vendor.oplus.hardware.fido.fido2ca@1.0-service.rc'
  'etc/init/vendor.oplus.hardware.fido.fidoca@1.0-service.rc'
  'etc/init/vendor.oplus.hardware.riskdetect-V1-service.rc'
)
for rel in "${FILES[@]}"; do
  [ -f "$WORK/src/$rel" ] || { echo "missing rc: $rel" >&2; exit 1; }
done
for rel in "${FILES[@]}"; do
  mkdir -p "$WORK/overlay/$(dirname "$rel")"
  tar --xattrs --xattrs-include='*' -C "$WORK/src" -cf - "$rel" | tar --xattrs --xattrs-include='*' -C "$WORK/overlay" -xf -
done
python3 - "$WORK/overlay" "${FILES[@]}" <<'PY'
import pathlib, sys
root=pathlib.Path(sys.argv[1])
targets=set(sys.argv[2:])
for rel in targets:
    p=root/rel
    lines=p.read_text(errors='surrogateescape').splitlines(keepends=True)
    out=[]; i=0; changed=False
    while i < len(lines):
        line=lines[i]
        stripped=line.strip()
        if stripped.startswith('service '):
            block=[line]; i+=1
            while i < len(lines) and lines[i].strip() and not lines[i].lstrip().startswith('on '):
                block.append(lines[i]); i+=1
            if not any(x.strip().startswith('disabled') for x in block):
                # Insert before trailing blank line if present.
                block.append('    disabled\n'); changed=True
            out.extend(block)
            continue
        out.append(line); i+=1
    if not changed:
        raise SystemExit(f'no service block modified in {rel}')
    p.write_text(''.join(out), errors='surrogateescape')
PY
# Verify every target block has disabled.
python3 - "$WORK/overlay" "${FILES[@]}" <<'PY'
import pathlib, sys
root=pathlib.Path(sys.argv[1])
for rel in sys.argv[2:]:
    text=(root/rel).read_text(errors='surrogateescape')
    if 'disabled' not in text:
        raise SystemExit(f'missing disabled in {rel}')
    print('PATCHED', rel)
PY

cp "$POLICY" "$WORK/policy/etc/selinux/precompiled_sepolicy"
chmod 644 "$WORK/policy/etc/selinux/precompiled_sepolicy"
setfattr -n security.selinux -v 'u:object_r:sepolicy_file:s0' "$WORK/policy/etc/selinux/precompiled_sepolicy"

ARCHIVE="$WORK/odm-v3.tar"
EXCLUDES=(--exclude='./etc/selinux/precompiled_sepolicy')
for rel in "${FILES[@]}"; do EXCLUDES+=(--exclude="./$rel"); done
cd "$WORK/src"
tar --format=gnu --xattrs --xattrs-include='*' --numeric-owner \
  -cf "$ARCHIVE" "${EXCLUDES[@]}" .
tar --format=gnu --xattrs --xattrs-include='*' --numeric-owner \
  -rf "$ARCHIVE" -C "$WORK/policy" ./etc/selinux/precompiled_sepolicy
tar --format=gnu --xattrs --xattrs-include='*' --numeric-owner \
  -rf "$ARCHIVE" -C "$WORK/overlay" ./etc/init/init.touchDaemon.rc \
      './etc/init/vendor.oplus.hardware.biometrics.face@1.0-service.rc' \
      './etc/init/vendor.oplus.hardware.biometrics.fingerprintpay@1.0-service.rc' \
      './etc/init/vendor.oplus.hardware.fido.fido2ca@1.0-service.rc' \
      './etc/init/vendor.oplus.hardware.fido.fidoca@1.0-service.rc' \
      './etc/init/vendor.oplus.hardware.riskdetect-V1-service.rc'
cat "$ARCHIVE" | "$MKFS" --tar=f -zlz4 -b4096 -C1048576 \
  -L odm -T1793346620 -U2f2ea3d1-c76b-5f2c-b99b-45ba6421cc21 "$OUT"
"$FSCK" "$OUT"

CHECK="$WORK/check"
mkdir -p "$CHECK"
mount -t erofs -o loop,ro "$OUT" "$CHECK"
test "$(sha256sum "$CHECK/etc/selinux/precompiled_sepolicy" | cut -d' ' -f1)" = "$(sha256sum "$POLICY" | cut -d' ' -f1)"
for rel in "${FILES[@]}"; do
  if ! grep -q '^[[:space:]]*disabled' "$CHECK/$rel"; then echo "not disabled: $rel" >&2; exit 1; fi
done
test ! -e "$CHECK/etc/vintf/manifest/network_manifest.xml"
umount "$CHECK"
echo 'ODM_V3_OK'
sha256sum "$OUT"
stat -c '%s %n' "$OUT"