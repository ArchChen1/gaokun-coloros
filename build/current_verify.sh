#!/usr/bin/env bash
# 基座断言闸门：任一条 FAIL 就 VERIFY_FAILED 退出非零，pack 会因此拒绝出包。
set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/env.sh"

fail=0
chk() { if eval "$2" >/dev/null 2>&1; then printf '  OK   %s\n' "$1"; else printf '  FAIL %s\n' "$1"; fail=1; fi; }

echo "== 0. 路径"
echo "  WORKDIR=$GK3_WORKDIR"
echo "  STATE  =$GK3_STATE"
chk "输入 vendor_base.img 存在" '[ -s "$GK3_VENDOR_BASE" ]'
chk "输入 my_product.erofs 存在" '[ -s "$GK3_MY_PRODUCT" ]'
chk "输入 my_stock.erofs 存在" '[ -s "$GK3_MY_STOCK" ]'
chk "解包树 system 存在" '[ -d "$GK3_SYS" ]'
chk "解包树 odm 存在" '[ -d "$GK3_ODM" ]'

echo '== 1. system 树'
chk "ath11k 固件 4 件齐全" 'for f in amss.bin board-2.bin m3.bin regdb.bin; do [ -s "$GK3_SYS/etc/firmware/ath11k/WCN6855/hw2.1/$f" ] || exit 1; done'
chk "rc 有密度属性触发" 'grep -q "on property:persist.sys.display.density=480" "$GK3_SYS/etc/init/gaokun3-v43.rc"'
chk "postboot 不再 kill SystemUI" '! grep -qE "kill (-9|-TERM) .*systemui|pkill -f com.android.systemui" "$GK3_SYS/etc/gaokun3-postboot.sh"'
chk "postboot 会调充电挂载脚本" 'grep -q "gk3-charge-apply.sh" "$GK3_SYS/etc/gaokun3-postboot.sh"'
chk "充电补丁二进制在 system 内" '[ -s "$GK3_SYS/etc/gk3-charge/SystemUI.apk" ] && [ -d "$GK3_SYS/etc/gk3-charge/empty" ]'
chk "postboot 可执行位" '[ -x "$GK3_SYS/etc/gaokun3-postboot.sh" ]'

echo '== 2. odm 树'
chk "libjsoncpp.so 在 odm/lib64" '[ -s "$GK3_ODM/lib64/libjsoncpp.so" ]'
chk "android.hardware.sensors-V3-ndk.so 在 odm/lib64" '[ -s "$GK3_ODM/lib64/android.hardware.sensors-V3-ndk.so" ]'
chk "libhidltransport.so 在 odm/lib64" '[ -s "$GK3_ODM/lib64/libhidltransport.so" ]'

echo '== 3. 基座 vendor 镜像'
if [ -f "$GK3_PARTS/vendor.img" ]; then
  mkdir -p /mnt/cv; umount /mnt/cv 2>/dev/null || true
  if mount -t ext4 -o loop,ro "$GK3_PARTS/vendor.img" /mnt/cv 2>/dev/null; then
    chk "turnip 驱动 = 7619b128…1d90（黑屏修复位）" '[ "$(sha256sum /mnt/cv/lib64/hw/vulkan.freedreno.so | cut -d" " -f1)" = "7619b1286b7d0b2d697e0c48b6a471ab7f439eee0523ce1820fee6ba612b1d90" ]'
    chk "debug.hwui.renderer=skiavk" 'grep -q "^debug.hwui.renderer=skiavk$" /mnt/cv/build.prop'
    chk "vendor rc 已去掉同步 ath11k bind" '! grep -qE "^[[:space:]]*write /sys/bus/pci/drivers/ath11k_pci/bind" /mnt/cv/etc/init/hw/init.gaokun3.rc'
    chk "vendor rc 有非阻塞 bind 兜底" 'grep -q "exec_background - root root -- /system/bin/sh -c" /mnt/cv/etc/init/hw/init.gaokun3.rc'
    chk "v29 抓取脚本已换标签" 'getfattr -n security.selinux --only-values /mnt/cv/bin/v29_usb_capture.sh 2>/dev/null | grep -q gaokun3_wlanap_exec'
  else
    printf '  FAIL vendor 镜像挂载失败\n'; fail=1
  fi
  umount /mnt/cv 2>/dev/null || true
else
  printf '  FAIL 尚未构建基座 vendor.img（先跑 make parts）\n'; fail=1
fi

echo '== 4. 分区产物与 src'
if [ "${GK3_ALLOW_MISSING_PARTS:-0}" = 1 ]; then
  # current_build.sh 第 3 步调用：system/odm 还没重打，这里不能当失败
  printf '  SKIP parts/system.erofs（构建中）\n  SKIP parts/odm.erofs（构建中）\n'
else
  chk "parts/system.erofs" '[ -s "$GK3_PARTS/system.erofs" ]'
  chk "parts/odm.erofs" '[ -s "$GK3_PARTS/odm.erofs" ]'
fi
chk "parts/my_product.erofs" '[ -e "$GK3_PARTS/my_product.erofs" ]'
chk "parts/my_stock.erofs" '[ -e "$GK3_PARTS/my_stock.erofs" ]'
for p in system_ext product my_manifest my_region my_engineering my_heytap my_carrier my_bigball; do
  chk "src/${p}_a.img 存在" '[ -s "$GK3_SRC/${p}_a.img" ]'
done

if [ $fail -ne 0 ]; then echo 'VERIFY_FAILED'; exit 1; fi
echo 'VERIFY_OK'
