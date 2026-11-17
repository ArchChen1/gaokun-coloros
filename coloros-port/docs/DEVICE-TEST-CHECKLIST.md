# Device test checklist

Run this after every bootable image. Record the image SHA-256, slot, kernel
version and test time. A feature that was not tested is not "working".

## Boot

- [ ] UEFI/systemd-boot entry selects the expected slot.
- [ ] kernel and DTB match the recorded build.
- [ ] first-stage init mounts system/system_ext/product/vendor.
- [ ] /data and /metadata mount.
- [ ] zygote/system_server survives five minutes.
- [ ] SurfaceFlinger stays alive.
- [ ] adb shell and root work.
- [ ] no watchdog or rescue-party restart loop.

## Display and input

- [ ] native resolution and orientation.
- [ ] brightness range, no black flash.
- [ ] 60 Hz and 120 Hz modes.
- [ ] touch coordinates and multi-touch.
- [ ] palm rejection and pen hover.
- [ ] pen pressure and tilt.
- [ ] pen side button.
- [ ] magnetic keyboard.
- [ ] touchpad click and two-finger scroll.

## Network, audio and power

- [ ] Wi-Fi scan, connect, reconnect after suspend.
- [ ] Bluetooth pairing and BLE HID.
- [ ] speaker left/right.
- [ ] microphone capture.
- [ ] wired and USB audio.
- [ ] battery percentage and charging state.
- [ ] suspend power and wake.
- [ ] thermal throttling and no false shutdown.

## Camera and media

- [ ] front camera preview and still image.
- [ ] rear camera preview and still image.
- [ ] 1080p recording.
- [ ] hardware video decode.
- [ ] one hardware encode session.

## Recovery

- [ ] boot menu is reachable without Android.
- [ ] the recorded ESP/boot backup restores the previous system.
- [ ] flashing only super leaves Windows and ESP untouched.
- [ ] userdata wipe is explicit and separately confirmed.
