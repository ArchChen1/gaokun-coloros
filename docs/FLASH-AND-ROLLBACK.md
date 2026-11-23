# Flash and rollback

## Current release

~~~text
release directory: coloros-port/out/release-coloros-b
boot.img SHA-256:  ec30855ece57548950851ccccfb695f169369a2e3d2e2cacca1ebdcda588193b
super.img.zst SHA-256: 26e45d05167e38423ea4c1c0d32d738e334e6cdf55ff081dbe6ef7cb65dfe2dd
raw super SHA-256: 5a71320b4796775480894db8f506e3aaa6e5060c7947fd054b3ffe0fd322ac01
~~~

The current package is the ColorOS ODM policy merge candidate. It still needs
a device boot test; do not treat it as a daily-driver release.

## Before the first write

1. Boot a Linux live USB.
2. Run backup_partitions.py against the whole disk.
3. Verify the backup SHA-256 files and test that the disk is visible after a
   reboot.
4. Confirm Secure Boot is disabled and the Android partition labels are
   super, userdata and metadata.
5. Confirm the chosen disk is the internal NVMe, not the USB live disk.

## Dry run

~~~bash
python3 scripts/flash_super.py \
  --disk /dev/nvme0n1 \
  --image out/super.raw.img \
  --confirm-device gaokun3
~~~

This prints the partition, image size and SHA-256. It performs no write.

## Write

Only after the dry run is correct:

~~~bash
sudo python3 scripts/flash_super.py \
  --disk /dev/nvme0n1 \
  --image out/super.raw.img \
  --confirm-device gaokun3 \
  --write
~~~

The script only writes the existing super partition. It does not touch ESP,
boot, Windows, userdata or metadata.

## If it does not boot

1. Stop retrying before the slot logic rewrites anything.
2. Boot the Linux live USB.
3. Collect pstore, the last boot logs and the partition report.
4. Restore ESP/boot/metadata from the verified backup.
5. Restore the previous super image.
6. Only then try a new patch.

A failed boot is expected during Gate 1. A failed rollback is not acceptable.
