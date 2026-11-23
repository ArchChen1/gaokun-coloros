#!/usr/bin/env bash
# 当前构建基座的硬断言。任一 FAIL → 退出非零，pack 必须拒绝出包。
set -uo pipefail
ROOT=/home/cenmin/coloros-build/current
PARTS=$ROOT/parts
SYS=/home/cenmin/v50-build/system/system
ODM=/home/cenmin/v50-build/odm
VENDOR=$PARTS/vendor.img

fail=0
chk() { if eval "$2" >/dev/null 2>&1; then printf '  OK   %s\n' "$1"; else printf '  FAIL %s\n' "$1"; fail=1; fi; }

echo '== 1. system 树'
chk "ath11k 固件 4 件齐全" 'for f in amss.bin board-2.bin m3.bin regdb.bin; do [ -s "$SYS/etc/firmware/ath11k/WCN6855/hw2.1/$f" ] || exit 1; done'
chk "rc 有密度属性触发" 'grep -q "on property:persist.sys.display.density=480" "$SYS/etc/init/gaokun3-v43.rc"'
chk "postboot 不再 kill SystemUI" '! grep -qE "kill (-9|-TERM) .*systemui|pkill -f com.android.systemui" "$SYS/etc/gaokun3-postboot.sh"'
chk "postboot 会调充电挂载脚本" 'grep -q "gk3-charge-apply.sh" "$SYS/etc/gaokun3-postboot.sh"'
chk "充电补丁二进制在 system 内" '[ -s "$SYS/etc/gk3-charge/SystemUI.apk" ] && [ -d "$SYS/etc/gk3-charge/empty" ]'
chk "postboot 可执行位" '[ -x "$SYS/etc/gaokun3-postboot.sh" ]'

echo '== 2. odm 树'
chk "libjsoncpp.so 在 odm/lib64" '[ -s "$ODM/lib64/libjsoncpp.so" ]'

echo '== 3. vendor 镜像'
if [ -f "$VENDOR" ]; then
  mkdir -p /mnt/cv; umount /mnt/cv 2>/dev/null
  if mount -t ext4 -o loop,ro "$VENDOR" /mnt/cv 2>/dev/null; then
    chk "turnip 驱动 = 7619b128…1d90（黑屏修复位）" '[ "$(sha256sum /mnt/cv/lib64/hw/vulkan.freedreno.so | cut -d" " -f1)" = "7619b1286b7d0b2d697e0c48b6a471ab7f439eee0523ce1820fee6ba612b1d90" ]'
    chk "debug.hwui.renderer=skiavk" 'grep -q "^debug.hwui.renderer=skiavk$" /mnt/cv/build.prop'
    chk "vendor rc 已去掉同步 ath11k bind" '! grep -qE "^[[:space:]]*write /sys/bus/pci/drivers/ath11k_pci/bind" /mnt/cv/etc/init/hw/init.gaokun3.rc'
    chk "vendor rc 有非阻塞 bind 兜底" 'grep -q "exec_background - root root -- /system/bin/sh -c" /mnt/cv/etc/init/hw/init.gaokun3.rc'
    chk "v29 抓取脚本已换标签" 'getfattr -n security.selinux --only-values /mnt/cv/bin/v29_usb_capture.sh 2>/dev/null | grep -q gaokun3_wlanap_exec'
    umount /mnt/cv
  else
    printf '  FAIL vendor 镜像挂载失败\n'; fail=1
  fi
else
  printf '  FAIL vendor 镜像不存在: %s\n' "$VENDOR"; fail=1
fi

echo '== 4. 其余分区'
for p in my_product my_stock; do chk "$p 存在" '[ -s "$PARTS/$p.erofs" ]'; done
for p in system_ext product my_manifest my_region my_engineering my_heytap my_carrier my_bigball; do
  chk "src/$p 存在" '[ -s "/home/cenmin/coloros-build/v49/src/${p}_a.img" ]'
done

if [ $fail -ne 0 ]; then echo 'VERIFY_FAILED'; exit 1; fi
echo 'VERIFY_OK'
