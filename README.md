# gaokun-coloros

Research and tooling for porting a ColorOS tablet system to the Huawei
MateBook E Go (gaokun3 / SC8280XP), based on the hardware bring-up from
`vahiru/gaokun-android`.

## Current state

- ColorOS 17 / Android 17 donor inspection is complete.
- Full OTA payload extraction, sparse conversion and liblp `super` assembly
  are implemented.
- `release-coloros-v5` is the current candidate (crDroid graphics stack swapped into ColorOS `system`).
- v5 has not yet been boot-tested on the E Go; see `coloros-port/docs/BRINGUP-v5.md` for the bring-up log.
- The official gaokun installer requires uninstalling an existing Android
  installation before reinstalling, so the install procedure is documented
  explicitly.

## Repository layout

- `coloros-port/` - scripts, tests, configuration and documentation.
- `coloros-port/docs/INSTALL-WHEN-ANDROID-EXISTS.md` - official installer flow.
- `coloros-port/docs/SELINUX-MERGE.md` - current policy merge method and hashes.
- `coloros-port/docs/DEVICE-TEST-CHECKLIST.md` - post-boot acceptance checks.
- `coloros-port/docs/PATCHING.md` - ColorOS binary and framework patch policy.

## Local-only data

ROMs, partition images, extracted donor trees, installer releases and
reference repositories are intentionally ignored. A clone of this repository
contains tooling and documentation only.

## Tests

~~~powershell
cd coloros-port
python -m unittest discover -s tests -v
python tests/smoke_pipeline.py
~~~

## Status

The project is at the first boot-test gate. Do not treat the generated image
as a daily-driver release.
