# Patch strategy

ColorOS patches must be tied to an exact donor and binary SHA-256. Never copy
an offset from HyperOS, MIUI, or another ColorOS device.

## First scan

Run scan_oppo_deps.py on each extracted ColorOS system tree. The report lists:

- waitForService / checkService sites;
- OPPO interface names;
- OPPO/vendor service strings.

Prioritise files in the boot path: surfaceflinger, system_server jars,
display, charger, thermal, audio and camera services.

## Patch order

1. Replace a blocking waitForService with checkService only when the caller
   already handles a missing binder.
2. Add a null/missing-service guard at the framework call site.
3. Add an AIDL shim only for a stable, documented interface.
4. Add SELinux rules last; never make the whole system permissive for a release.

## Jar and APK edits

- Preserve the original signing block whenever possible.
- If a boot jar changes, remove the prebuilt boot image and let odrefresh build
  a signed image in /data.
- Do not rename a vendor HAL library. Use ro.hardware.<class>.<instance>.
- Record input SHA-256, output SHA-256 and every changed method/offset.

## Required evidence

Every patch needs:

- donor build fingerprint;
- exact file and SHA-256;
- disassembly or stack trace showing the blocked call;
- before/after logcat;
- a clean-flash test, not only a dirty flash.
