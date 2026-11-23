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
- [ ] On a clean EGO install, verify that the boot script sets `settings_shutdown_adfr_oti=1` for the active user and ColorOS does not switch the panel mode on touch or keyboard wake. The v43 live reference used `min_refresh_rate=119.99989` and `peak_refresh_rate=120.0`.
- [ ] After a reboot, repeat the 120 Hz check with continuous touch, then leave the wireless keyboard idle and wake it with a key. Check for lost touch, a black flash, or snow.
- [ ] On a clean install, complete the supported first-run flow. Verify that three-button navigation and gestures each support Back, Home, and Recents, and that the control center can open Settings and WLAN settings.
- [ ] Verify that the system reports a base logical density of 320 dpi and that the release post-boot script sets the accepted 280 dpi user override (914 dp smallest width) with font scale 1.25. Check app and home screen layout on a clean install and after a reboot.
- [ ] With the 280 dpi user override, verify that `persist.sys.display.density` reads 320 after a clean boot and after a reboot. In landscape, compare the Smart Sidebar against the accepted v43 wide layout (256 px list and 88 px Transfer Dock icon). Check its labels, edge handle and touch targets in both orientations.
- [ ] Compare the control center tiles, sliders and settings button against the v43 baseline at 280 dpi in both orientations.
- [ ] touch coordinates and multi-touch.
- [ ] With the M-Pencil input enabled and the pen away from the display, draw slow continuous loops with a finger. Touch must stay continuous and the system must not report pen hover. Repeat with the pen nearby and out of sensing range. See `reports/V43-TOUCH-POWER-2026-11-22.md` for the v43 candidate.
- [ ] palm rejection and pen hover.
- [ ] pen pressure and tilt.
- [ ] pen side button.
- [ ] wireless keyboard, including after idle.
- [ ] touchpad click and two-finger scroll.

## Network, audio and power

- [ ] Wi-Fi scan, connect, reconnect after suspend.
- [ ] After a cold boot, launch 小布助手 from Home and open 账号中心 from Settings. Both should reach their own screens without the “定制应用” compatibility warning. Verify a voice request and account sign-in separately.
- [ ] Bluetooth pairing and BLE HID.
- [ ] With an OPPO Enco Free4, compare AAC and LHDC V5 at 48 and 96 kHz, and verify playback after reconnect. Check switching from AAC back to LHDC with the headphones off the ears and volume low; no white noise should occur. Verify actual playback before listing 192 kHz as supported. See `reports/V43-BLUETOOTH-AUDIO-2026-11-22.md`.
- [ ] speaker left/right.
- [ ] microphone capture.
- [ ] wired and USB audio.
- [ ] Insert and remove a USB-C charger. Check that battery percentage and charging state track the main battery, that the status bar shows and clears the charging symbol, and that the ColorOS charging notice agrees.
- [ ] Integrate the validated charging-state patch in `config/v43-systemui-standard-charge.patch` using the release signing plan. Check that a clean install loads the new SystemUI and repeat the charger test after a reboot. Confirm the symbol stays off when the charger is connected and charging is paused. See `reports/V43-UI-CHARGING-2026-11-22.md`.
- [ ] suspend power and wake.
- [ ] Short-press the physical power key to put the display to sleep, then short-press to wake it. Verify after a clean install and after a reboot that both respond without the five-second diagnostics timeout. Check long press and the configured double-press action too.
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
