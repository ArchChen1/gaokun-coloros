# Donor requirements

The donor is a ColorOS tablet OTA from a Snapdragon device. It is not
distributed with this project.

## Preferred

- OPPO Pad Mini OPD2515 ColorOS 17 / Android 17, if the baseline is A17.
- A ColorOS 16 / Android 16 tablet build when the first PoC uses A16.

## Required partitions

- system
- system_ext
- product
- my_product
- my_manifest

## Useful partitions

- my_stock
- my_region
- my_heytap
- my_bigball
- my_carrier
- my_engineering

## Do not use

- MediaTek donor images with an SC8280XP target;
- a phone donor for the first tablet PoC;
- incremental OTA payloads without the matching source images;
- an OTA whose metadata does not identify the device and build.

Record the OTA path, SHA-256, device codename, build fingerprint and partition
list in reports/donor.json before building anything.
