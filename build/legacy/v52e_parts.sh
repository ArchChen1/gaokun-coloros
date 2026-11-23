#!/usr/bin/env bash
set -euo pipefail
V=/home/cenmin/v50-build
S=$V/system/system/etc
O=/home/cenmin/coloros-build/v52
MK=/home/cenmin/toolchain/erofs-install/bin/mkfs.erofs
FB=/home/cenmin/toolchain/erofs-install/bin/fsck.erofs

echo '== rewrite postboot (charge mount + single SystemUI restart + density watch)'
cat > "$S/gaokun3-postboot.sh" <<'EOS'
#!/system/bin/sh
# 1) charge icon: bind patched SystemUI + empty oat dir into zygote namespaces
/system/etc/gk3-charge-apply.sh
# 2) display density: ColorOS recomputes persist.sys.display.density (=480) at boot
setprop persist.sys.display.density 320
sleep 6
p=$(pidof com.android.systemui)
[ -n "$p" ] && kill -TERM $p
sleep 3
i=0
while [ $i -lt 20 ]; do
    sleep 3
    [ "$(getprop persist.sys.display.density)" = "320" ] || setprop persist.sys.display.density 320
    i=$((i+1))
done
# 3) misc one-shot settings
settings --user current put secure settings_shutdown_adfr_oti 1 2>/dev/null || true
settings put system min_refresh_rate 119.99989 2>/dev/null || true
settings put system peak_refresh_rate 120.0 2>/dev/null || true
settings put secure user_refresh_rate 120 2>/dev/null || true
settings put global device_provisioned 1 2>/dev/null || true
settings put secure user_setup_complete 1 2>/dev/null || true
EOS
chmod 755 "$S/gaokun3-postboot.sh"

echo '== rebuild system'
rm -f "$O"/system_a_v52e.erofs
"$MK" -zlz4 -b4096 -C65536 -L system "$O/system_a_v52e.erofs" "$V/system" >/dev/null
echo "system_a_v52e $(stat -c%s "$O/system_a_v52e.erofs")"
"$FB" "$O/system_a_v52e.erofs" >/dev/null 2>&1 && echo "fsck ok"
echo V52E_PARTS_DONE
