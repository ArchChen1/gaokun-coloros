#!/usr/bin/env bash
set -euo pipefail
V=/home/cenmin/v50-build
S=$V/system/system/etc
STAGE=$S/gk3-charge
CAND=/mnt/e/gaokun-coloros/coloros-port/work/v43-perf-live/ui-SystemUI-charge-test.apk

echo '== stage candidate apk'
mkdir -p "$STAGE/empty"
cp -f "$CAND" "$STAGE/SystemUI.apk"
sha256sum "$STAGE/SystemUI.apk"

echo '== write apply hook'
cat > "$S/gk3-charge-apply.sh" <<'EOS'
#!/system/bin/sh
# Bind the patched SystemUI (charge icon fix) and the empty dir over its oat
# into the zygote mount namespace, before/around the SystemUI (re)start.
stage=/system/etc/gk3-charge
base=/system_ext/priv-app/SystemUI
apk=$base/SystemUI.apk
oat=$base/oat
log=/metadata/gk3-charge.log
echo "start $(date)" >> $log
for pid in $(pidof zygote64); do
    nsenter -t "$pid" -m -- mount --bind "$stage/empty" "$oat" 2>>$log && echo "oat hidden $pid" >> $log
    nsenter -t "$pid" -m -- mount --bind "$stage/SystemUI.apk" "$apk" 2>>$log && echo "apk mounted $pid" >> $log
done
echo "done $(date)" >> $log
EOS
chmod 755 "$S/gk3-charge-apply.sh"

echo '== hook into postboot'
python3 - "$S/gaokun3-postboot.sh" <<'PY'
import sys
p = sys.argv[1]
d = open(p).read()
call = '/system/etc/gk3-charge-apply.sh\n'
if 'gk3-charge-apply.sh' not in d:
    d = d.replace('#!/system/bin/sh\n', '#!/system/bin/sh\n' + call, 1)
    open(p, 'w').write(d)
print(open(p).read())
PY

echo '== rebuild system (grown)'
O=/home/cenmin/coloros-build/v52
MK=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FB=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs
rm -f "$O"/system_a_v52d.erofs
"$MK" -zlz4 -b4096 -C65536 -L system "$O/system_a_v52d.erofs" "$V/system" >/dev/null
SZ=$(stat -c%s "$O/system_a_v52d.erofs")
echo "system_a_v52d $SZ"
"$FB" "$O/system_a_v52d.erofs" >/dev/null 2>&1 && echo "fsck ok"
echo V52D_PARTS_DONE
