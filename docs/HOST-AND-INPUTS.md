# Host and input preparation

## Supported host

Use Linux for image creation and flashing. Windows is fine for OTA inspection
and payload extraction, but ext4 loop mounting and block-device writes are
Linux-only.

Tested assumptions:

- Python 3.11 or newer;
- Linux with `lsblk`, `dd` and `mkfs.ext4` for device work;
- root only for the image and flash stages;
- at least 40 GiB free for a full staging tree, preferably 80 GiB.

Android SDK platform tools (`adb`) are required for diagnostics. They are not
required for offline OTA inspection.

## ColorOS donor

Provide a full OTA zip, not an incremental patch. Run:

~~~bash
python3 scripts/ota_inspect.py donor.zip --hash --report reports/donor.json
python3 scripts/preflight.py --donor reports/donor.json
~~~

Expected partition names include system, system_ext, product, my_product and
my_manifest. The report records the device/build metadata from the OTA when
available.

## gaokun3 baseline

Use the `vahiru/gaokun-android` Android 16 baseline that is already booting on
the tablet. For super repacking, take a complete `super` image, not only its
metadata. The repacker preserves non-selected partitions such as vendor by
copying their extents from the template.

If you only have a live device, capture super over ADB root before building.
The capture must be 12,884,901,888 bytes and its liblp geometry must report
3 metadata slots with 64 KiB metadata.

## Directory

Everything private belongs under `inputs/` and is ignored by git. Reports may
contain local paths; review them before publishing.
