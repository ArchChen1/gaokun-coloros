# Installing the ColorOS build when Android is already installed

The gaokun Android Windows installer 0.2.0 does **not** overwrite an existing
Android installation. When it detects Android on the system disk, it opens
Manage / Uninstall instead of the install flow.

## Correct path

1. Copy the release directory to Windows on the Ego:

   `out\release-coloros-a`

   It must contain:

   - `boot.img`
   - `super.img.zst`
   - `install-artifacts.sha256`

2. Back up any Android files you need. Uninstalling Android erases its data.

3. Open the gaokun Android installer 0.2.0.

4. On the check page, choose **Manage**.

5. Choose **Uninstall**. Let it complete. It removes the Android partitions
   and restores the EFI fallback boot file while preserving Windows and other
   EFI boot entries.

6. The freed space remains unallocated. You do not have to merge it into C:.
   Return to the installer start page and run **Check** again.

7. Start a normal install. Select the large unallocated region.

8. On the release page, choose **Local folder** and point it at the copied
   `release-coloros-a` directory.

9. Do not choose an online release. The installer must use the local ColorOS
   files.

10. Review the summary and hold to confirm.

## Do not do

- Do not delete Windows, EFI, recovery or unknown partitions manually.
- Do not use the online release source during this test.
- Do not run the installer while BitLocker is converting.
- Do not interrupt uninstall or install.

## Rollback

The official gaokun crDroid release files can be installed the same way if the
ColorOS test fails: uninstall the failed Android system, then install the
official release from its local directory or online source.

## Before uninstalling

- BitLocker recovery key available if BitLocker is enabled.
- Secure Boot disabled.
- Fast Startup disabled.
- AC power connected.
- Ego has enough contiguous free space after uninstall. The standard layout
  should already provide it; verify the installer shows one large unallocated
  span before confirming.
