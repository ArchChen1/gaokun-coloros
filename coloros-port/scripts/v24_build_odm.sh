#!/bin/bash
set -euo pipefail
ROOT=/home/cenmin
SRC=$ROOT/v5/parts/odm_v23_a.img
WORK=$ROOT/v24-work
OUT=$ROOT/v5/parts/odm_v24_a.img
MKFS=$ROOT/toolchain/erofs-install/bin/mkfs.erofs
FSCK=$ROOT/toolchain/erofs-install/bin/fsck.erofs
MOUNT=$WORK/src
EXTRACT=$WORK/extract
rm -rf "$WORK"
mkdir -p "$MOUNT" "$EXTRACT"
mount -t erofs -o loop,ro "$SRC" "$MOUNT"
cleanup(){ umount "$MOUNT" 2>/dev/null || true; }
trap cleanup EXIT
cp -a "$MOUNT/." "$EXTRACT/"
umount "$MOUNT"
# Remove only the audio-core IModule manifests that request non-existent providers.
rm -f "$EXTRACT/etc/vintf/manifest/manifest_module_binaural_record_V3.xml"
rm -f "$EXTRACT/etc/vintf/manifest/manifest_module_virtual_audio_v3.xml"
# Do not leave a policy include for virtual audio when its module manifest is removed.
python3 - "$EXTRACT/etc/audio/audio_policy_configuration.xml" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text(encoding='utf-8')
start='        <!-- #ifdef OPLUS_FEATURE_VIRTUAL_AUDIO -->'
end='        <!-- #endif OPLUS_FEATURE_VIRTUAL_AUDIO -->'
i=s.find(start)
j=s.find(end)
if i < 0 or j < i:
    raise SystemExit('virtual audio block not found')
j += len(end)
s=s[:i]+'        <!-- gaokun3 v24: virtual audio provider is not registered; module disabled at boot -->\n'+s[j:]
if '/odm/etc/virtual_audio_policy_configuration.xml' in s:
    raise SystemExit('virtual policy include remains')
p.write_text(s,encoding='utf-8')
PY
# Repack preserving SELinux xattrs.
rm -f "$OUT"
"$MKFS" -zlz4 -b4096 -C1048576 -L odm -T1793346620 -U2f2ea3d1-c76b-5f2c-b99b-45ba6421cc21 "$OUT" "$EXTRACT"
"$FSCK" "$OUT"
sha256sum "$OUT"
stat -c '%s %n' "$OUT"
echo ODM_V24_BUILT