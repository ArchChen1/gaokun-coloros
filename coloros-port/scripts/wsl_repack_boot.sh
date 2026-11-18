#!/usr/bin/env bash
set -euo pipefail
MKBOOTIMG=/mnt/e/gaokun-coloros/analysis/coloros_port/otatools/bin/mkbootimg
B=/home/cenmin/coloros-build/boot-unpack
OUT=/home/cenmin/coloros-build/boot-coloros.img
"$MKBOOTIMG" \
  --header_version 2 \
  --os_version 17.0.0 \
  --os_patch_level 2026-10 \
  --kernel "$B/kernel" \
  --ramdisk "$B/ramdisk.new" \
  --dtb "$B/dtb" \
  --pagesize 0x00000800 \
  --base 0x00000000 \
  --kernel_offset 0x10008000 \
  --ramdisk_offset 0x11000000 \
  --second_offset 0x00000000 \
  --tags_offset 0x10000100 \
  --dtb_offset 0x0000000011f00000 \
  --board "" \
  --cmdline "androidboot.flash.locked=0 androidboot.verifiedbootstate=orange iommu.passthrough=0 iommu.strict=0 androidboot.hardware=gaokun3 androidboot.boot_devices=soc@0/1c20000.pcie androidboot.selinux=enforcing androidboot.veritymode=disabled firmware_class.path=/vendor/firmware/ init=/init printk.devkmsg=on deferred_probe_timeout=10 fw_devlink.sync_state=timeout console=tty0 clk_ignore_unused pd_ignore_unused arm64.nopauth efi=noruntime efi_pstore.pstore_disable=1 fbcon=rotate:1 usbhid.quirks=0x12d1:0x10b8:0x21000000 himax_hx83121a_spi.disable_pressure=0 snd_usb_audio.index=-2,-2,-2,-2" \
  --output "$OUT"
ls -lh "$OUT"
sha256sum "$OUT"
