# Roadmap

## Gate 0: donor and rollback

- Obtain a legally usable ColorOS tablet OTA. Prefer a Snapdragon donor with
  ColorOS 16 / Android 16 for the first PoC.
- Run ota_inspect.py. Record the exact SHA-256 and metadata.
- Confirm system, system_ext, product, my_product and my_manifest are present.
- Back up ESP, boot_a, boot_b, metadata, misc and super from the device.
- Do not continue if the rollback media has not been read back and verified.

## Gate 1: reach SurfaceFlinger

The first candidate is allowed to be incomplete. Success means:

- kernel and DTB from gaokun-android boot;
- first-stage init mounts the ColorOS system partitions;
- system_server stays alive for at least five minutes;
- SurfaceFlinger starts without waiting forever on an OPPO-only HAL;
- adb shell and logcat work;
- the device can be restored from the backup.

If system_server or SurfaceFlinger loops, stop and use collect_boot_diag.py.
Do not patch random binaries before identifying the blocked service.

## Gate 2: desktop and input

- display at native resolution, then 120 Hz;
- touch, keyboard, touchpad and pen input;
- Wi-Fi, Bluetooth and USB-C ADB;
- brightness and thermal shutdown thresholds;
- audio output and microphone;
- charging and battery reporting;
- suspend/resume.

## Gate 3: daily use

- camera, hardware decode/encode;
- ColorOS refresh-rate policy;
- audio routing and effects;
- pen pressure, hover and side button;
- long-uptime stability;
- SELinux enforcing;
- repeatable release builds and rollback.

## Non-goals

Do not promise OPPO cloud, Find My Device, secure payment, Widevine L1,
Play Integrity, OPPO OTA, cellular or GPS. The hardware or security chain for
these is absent.
