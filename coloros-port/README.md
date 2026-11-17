# ColorOS on Huawei MateBook E Go (gaokun3)

Working port project for bringing an OPPO tablet ColorOS build to the Huawei
MateBook E Go (SC8280XP / gaokun3), reusing the hardware bring-up from
[vahiru/gaokun-android](https://github.com/vahiru/gaokun-android).

## Status

Phase 0: project skeleton, donor preflight, OTA inspection, payload extraction,
liblp inspection/repacking, rollback planning and boot diagnostics.

No ROM image, vendor blob, OPPO APK or signing key is included. You must provide
a legally obtained ColorOS tablet OTA and a gaokun3 hardware baseline.

## Safety

- Back up ESP, boot, super, metadata and userdata before the first flash.
- Keep Secure Boot disabled while Android is installed.
- The first build is diagnostic, not a daily-driver release.
- Do not publish vendor images, OPPO APKs, signing keys, device serial numbers,
  or user data.
- `flash_super.py` is dry-run by default and only writes the `super` partition
  after both `--write` and `--confirm-device gaokun3`.

## Quick start

~~~powershell
# 1. Inspect an OTA zip without extracting it
python scripts/ota_inspect.py inputs/ColorOS-OPDxxxx.zip --report reports/donor.json

# 2. Check that the donor matches the planned target
python scripts/preflight.py --donor reports/donor.json

# 3. Extract full-OTA partition images
python scripts/payload_extract.py inputs/ColorOS-OPDxxxx.zip --output work/parts

# 4. Inspect a raw, sparse or super image
python scripts/partition_inspect.py work/parts/system.img
python scripts/partition_inspect.py out/super.raw.img --partitions

# 5. Scan the ColorOS tree for OPPO-private HAL dependencies
python scripts/scan_oppo_deps.py work/parts/system --json reports/oppo-deps.json
~~~

The Linux-only image-building path is documented in `docs/ROADMAP.md` and
`scripts/build.py`. The image stage needs root, loop devices and `mkfs.ext4`.

## Layout

- `scripts/` - donor inspection, super repacking, flashing and diagnostics.
- `config/` - target contract and donor expectations.
- `docs/` - roadmap, patch strategy, donor requirements and device checklist.
- `inputs/` - donor OTA and extracted images (ignored by git).
- `work/` - scratch space (ignored by git).
- `out/` - locally built artifacts (ignored by git).
- `reports/` - machine-readable inspection reports.

## Tests

~~~powershell
python -m unittest discover -s tests -v
~~~

Synthetic tests cover sparse images, liblp parsing, `super` repacking with
vendor preservation, OTA manifest inspection, payload extraction, preflight and
dependency scanning. They do not replace a real donor boot test.

## Next gate

Provide a ColorOS tablet OTA and the gaokun3 baseline `super` metadata. The
first measurable milestone is reaching a live SurfaceFlinger and system_server
without a repeated watchdog reset, followed by the device checklist.
