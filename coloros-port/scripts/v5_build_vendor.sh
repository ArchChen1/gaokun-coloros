set -u
CB=/home/cenmin/coloros-build
BASE=$CB/vendor-gaokun-v4.img
OUT=$CB/vendor-gaokun-v5.img
CAP=/mnt/d/gaokun-build-temp/gk3-capture-v5.sh
RC=$CB/smmustall-v5.rc

echo "########## clean rebuild from v4 baseline ##########"
cp -f "$BASE" "$OUT"

debugfs -R "dump /etc/init/smmustall.rc /tmp/rc.orig" "$OUT" >/dev/null 2>&1
tr -d '\r' < /tmp/rc.orig > "$RC"
echo "orig rc gk3-capture refs: $(grep -c 'gk3-capture' $RC || true)"
cat >> "$RC" <<'RCEOF'

# ---- temporary diagnostic capture (v5) ----
service gk3-capture /vendor/bin/gk3-capture.sh
    class late_start
    user root
    group root system
    disabled

on post-fs-data
    start gk3-capture
RCEOF
echo "new rc gk3-capture refs: $(grep -c 'gk3-capture' $RC)   CR: $(tr -cd '\r' < $RC | wc -c)"

cat > /tmp/dbg5.cmd <<'CMDEOF'
rm /bin/gk3-capture.sh
write /mnt/d/gaokun-build-temp/gk3-capture-v5.sh /bin/gk3-capture.sh
set_inode_field /bin/gk3-capture.sh mode 0100755
set_inode_field /bin/gk3-capture.sh uid 0
set_inode_field /bin/gk3-capture.sh gid 2000
ea_set /bin/gk3-capture.sh security.selinux u:object_r:gaokun3_smmustall_exec:s0
rm /etc/init/smmustall.rc
write /home/cenmin/coloros-build/smmustall-v5.rc /etc/init/smmustall.rc
set_inode_field /etc/init/smmustall.rc mode 0100644
set_inode_field /etc/init/smmustall.rc uid 0
set_inode_field /etc/init/smmustall.rc gid 0
ea_set /etc/init/smmustall.rc security.selinux u:object_r:vendor_configs_file:s0
CMDEOF
debugfs -w -f /tmp/dbg5.cmd "$OUT" 2>&1 | grep -E 'Allocated|error' | head

e2fsck -fy "$OUT" 2>&1 | tail -3

echo
echo "########## verify v5 vendor ##########"
echo "-- capture script --"
debugfs -R "dump /bin/gk3-capture.sh /tmp/cap.out" "$OUT" >/dev/null 2>&1
sha256sum /tmp/cap.out
echo "   CR count: $(tr -cd '\r' < /tmp/cap.out | wc -c)  (want 0)"
echo "-- rc: service definitions --"
debugfs -R "cat /etc/init/smmustall.rc" "$OUT" 2>/dev/null > /tmp/rc.out
echo "   'service gk3-capture' count: $(grep -c 'service gk3-capture' /tmp/rc.out)  (want 1)"
echo "   'on post-fs-data' count:     $(grep -c 'on post-fs-data' /tmp/rc.out)"
grep -n 'gk3-capture' /tmp/rc.out
echo "-- media_profiles fix --"
debugfs -R "stat /etc/media_profiles_vendor.xml" "$OUT" 2>&1 | grep -E 'Size:|Links:'
echo "-- smmu-nostall (want 315a1e4b...) --"
debugfs -R "cat /bin/smmu-nostall.sh" "$OUT" 2>/dev/null | sha256sum
echo "-- free --"
dumpe2fs -h "$OUT" 2>/dev/null | grep -E 'Free blocks|Free inodes'
ls -l "$OUT"
echo VENDOR_V5_OK