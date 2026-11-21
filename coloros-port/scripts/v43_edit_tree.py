#!/usr/bin/env python3
"""Apply the v43 static policy to an extracted Android partition tree."""

import hashlib
import os
import re
import shutil
import struct
import sys
from pathlib import Path

SYSTEM_LABEL = 'u:object_r:system_file:s0'
VENDOR_LABEL = 'u:object_r:vendor_configs_file:s0'


def label(path, value):
    try:
        os.setxattr(path, 'security.selinux', (value + '\0').encode(),
                    follow_symlinks=False)
    except OSError as exc:
        print('warning: cannot set label %s: %s' % (path, exc), file=sys.stderr)


def write_text(path, text, mode=0o644, typ=SYSTEM_LABEL):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    os.chmod(path, mode)
    os.chown(path, 0, 0)
    label(path, typ)


def props(path, values):
    path = Path(path)
    text = path.read_text(encoding='utf-8')
    keys = set(values)
    lines = []
    for line in text.splitlines():
        key = line.split('=', 1)[0].strip().rstrip('?')
        if key in keys:
            continue
        lines.append(line)
    for key, value in values.items():
        lines.append('%s=%s' % (key, value))
    with path.open('w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')


def append(path, text):
    path = Path(path)
    with path.open('a', encoding='utf-8', newline='\n') as f:
        f.write(text)


def disable_service(path, names):
    path = Path(path)
    if not path.is_file():
        return
    lines = path.read_text(encoding='utf-8').splitlines()
    wanted = set(names)
    out = []
    i = 0
    while i < len(lines):
        m = re.match(r'^service\s+(\S+)\s+', lines[i])
        if not m:
            out.append(lines[i])
            i += 1
            continue
        name = m.group(1)
        block = [lines[i]]
        j = i + 1
        while j < len(lines) and (lines[j].startswith(('    ', '\t')) or
                                  lines[j].strip() == ''):
            block.append(lines[j])
            j += 1
        if name in wanted and not any(x.strip() == 'disabled' for x in block):
            block.insert(1, '    disabled')
        out.extend(block)
        i = j
    path.write_text('\n'.join(out) + '\n', encoding='utf-8')
def remove_service(path, name):
    path = Path(path)
    if not path.is_file():
        return
    lines = path.read_text(encoding='utf-8').splitlines()
    out = []
    i = 0
    while i < len(lines):
        if re.match(r'^service\s+' + re.escape(name) + r'\s+', lines[i]):
            i += 1
            while i < len(lines) and (lines[i].startswith(('    ', '\t')) or
                                      lines[i].strip() == ''):
                i += 1
            continue
        if re.match(r'^\s*start\s+' + re.escape(name) + r'\s*$', lines[i]):
            i += 1
            continue
        out.append(lines[i])
        i += 1
    path.write_text('\n'.join(out) + '\n', encoding='utf-8')


def remove_paths(root, paths):
    for rel in paths:
        p = Path(root) / rel
        if p.is_dir():
            shutil.rmtree(p)
        elif p.exists() or p.is_symlink():
            p.unlink()


def patch_system(root):
    root = Path(root)
    props(root / 'system/build.prop', {
        'ro.zygote': 'zygote64_32',
        'ro.product.cpu.abilist': 'arm64-v8a,armeabi-v7a,armeabi',
        'ro.product.cpu.abilist32': 'armeabi-v7a,armeabi',
        'ro.product.cpu.abilist64': 'arm64-v8a',
        'ro.radio.noril': 'true',
        'ro.adb.secure': '0',
        'ro.mediaserver.64b.enable': 'true',
        'ro.surface_flinger.supports_background_blur': '0',
        'persist.sys.background_blur_supported': 'false',
        'persist.debug.wfd.enable': '0',
        'persist.sys.usb.config': 'adb',
        'persist.adb.tcp.port': '5555',
        'persist.sys.disable_rescue': 'true',
        'debug.sf.auto_latch_unsignaled': '1',
    })
    write_text(root / 'system/etc/sysconfig/gaokun3-components.xml', '''<permissions>
    <component-override package="org.codeaurora.ims">
        <component class="org.codeaurora.ims.ImsService" enabled="false" />
    </component-override>
    <component-override package="com.coloros.findmyphone">
        <component class="com.oplus.find.provider.FindProvider" enabled="false" />
    </component-override>
</permissions>
''')
    write_text(root / 'system/etc/init/gaokun3-v43.rc', '''# gaokun3 v43: boot policy that is safe before framework startup.
on post-fs-data
    setprop debug.sf.auto_latch_unsignaled 1
    setprop persist.sys.background_blur_supported false
    setprop persist.debug.wfd.enable 0

on property:sys.boot_completed=1
    write /sys/class/devfreq/3d00000.gpu/min_freq 690000000
    exec_background - root root -- /system/bin/sh /system/etc/gaokun3-postboot.sh
''')
    write_text(root / 'system/etc/gaokun3-postboot.sh', '''#!/system/bin/sh
# Run only after the framework reports a completed boot.
settings put system min_refresh_rate 120.0 2>/dev/null || true
settings put system peak_refresh_rate 120.0 2>/dev/null || true
settings put secure user_refresh_rate 120 2>/dev/null || true
settings put system font_scale 1.25 2>/dev/null || true
wm density 320 2>/dev/null || true
''', mode=0o755)


def patch_vendor(root):
    root = Path(root)
    light = root / 'bin/hw/android.hardware.light-service.gaokun3'
    data = bytearray(light.read_bytes())
    if hashlib.sha256(data).hexdigest() == '3f1690d396e9269f699f37781074e75f7db000b71abc3db10554fa02b56fca13':
        if struct.unpack_from('<I', data, 0x393d4)[0] != 0x53087d08:
            raise SystemExit('unexpected light-service instruction')
        struct.pack_into('<I', data, 0x393d4, 0x39400048)
        with light.open('r+b') as f:
            f.write(data)
    else:
        raise SystemExit('unexpected light-service hash')
    props(root / 'build.prop', {
        'ro.radio.noril': 'true',
        'ro.surface_flinger.supports_background_blur': '0',
        'persist.sys.background_blur_supported': 'false',
        'debug.sf.auto_latch_unsignaled': '1',
    })
    # Match the HyperOS reference: declare absent hardware instead of
    # advertising donor-only feature XMLs.
    write_text(root / 'etc/permissions/gaokun3-unavailable-features.xml', '''<permissions>
    <unavailable-feature name="android.hardware.sensor.light" />
    <unavailable-feature name="android.hardware.sensor.compass" />
    <unavailable-feature name="android.hardware.location.gps" />
    <unavailable-feature name="android.hardware.telephony" />
    <unavailable-feature name="android.hardware.telephony.gsm" />
    <unavailable-feature name="android.hardware.telephony.cdma" />
    <unavailable-feature name="android.hardware.telephony.ims" />
    <unavailable-feature name="android.hardware.nfc" />
</permissions>
''', typ=VENDOR_LABEL)
    # The donor v4l2 Codec2 HAL cannot link against this vendor's
    # libcodec2_vndk.so. It is already dead on arrival in the v42 logs, so
    # disable it and remove its VINTF declaration instead of restarting it
    # every five seconds. The system software Codec2 store remains available.
    remove_paths(root, [
        'etc/vintf/manifest/android.hardware.media.c2-service-v4l2.xml',
    ])
    disable_service(root / 'etc/init/android.hardware.media.c2-service-v4l2.rc',
                    ['android-hardware-media-c2-v4l2-hal'])
    # Drop the old capture/probe route. Keep only the boot-completed marker.
    remove_paths(root, [
        'etc/init/gk3-capture.rc',
        'bin/gk3-capture.sh',
        'bin/v38r3_dump.sh',
        'bin/v40_dump.sh',
    ])
    remove_service(root / 'etc/init/smmustall.rc', 'gk3-capture')
    rc = root / 'etc/init/hw/init.gaokun3.rc'
    remove_service(rc, 'gk3_capture32')
    text = rc.read_text(encoding='utf-8')
    text = re.sub(r'\n# gaokun3 v38r3:.*?(?=\n# gaokun3 v40:)', '\n', text, flags=re.S)
    text = re.sub(r'\n# gaokun3 v40:.*?(?=\n# gaokun3 v41:)', '\n', text, flags=re.S)
    rc.write_text(text, encoding='utf-8')
    append(rc, '''
# gaokun3 v43: keep the display path deterministic after boot.
on post-fs-data
    setprop debug.sf.auto_latch_unsignaled 1
    setprop persist.sys.background_blur_supported false
    setprop persist.debug.wfd.enable 0

on property:sys.boot_completed=1
    write /sys/class/devfreq/3d00000.gpu/min_freq 690000000
    exec_background - root root -- /system/bin/sh /system/etc/gaokun3-postboot.sh
''')


def patch_odm(root):
    root = Path(root)
    props(root / 'build.prop', {
        'ro.zygote': 'zygote64_32',
        'ro.sf.lcd_density': '240',
        'ro.product.brand': 'Huawei',
        'ro.product.manufacturer': 'Huawei',
        'ro.product.model': 'MateBook E Go',
        'ro.product.name': 'gaokun3',
        'ro.product.device': 'gaokun3',
        'ro.product.odm.brand': 'Huawei',
        'ro.product.odm.manufacturer': 'Huawei',
        'ro.product.odm.model': 'MateBook E Go',
        'ro.product.odm.name': 'gaokun3',
        'ro.product.odm.device': 'gaokun3',
        'ro.product.vendor.brand': 'Huawei',
        'ro.product.vendor.manufacturer': 'Huawei',
        'ro.product.vendor.model': 'MateBook E Go',
        'ro.product.vendor.name': 'lineage_gaokun3',
        'ro.product.vendor.device': 'gaokun3',
        'ro.product.oplus.cpuinfo': 'SC8280XP',
        'ro.radio.noril': 'true',
        'ro.surface_flinger.supports_background_blur': '0',
        'persist.sys.background_blur_supported': 'false',
        'debug.sf.auto_latch_unsignaled': '1',
    })
    # These donor identities and services are not valid on gaokun3.
    remove_paths(root, [
        'etc/vintf/manifest/manifest_oplus_displaypanelfeature_aidl.xml',
        'etc/vintf/manifest/vintf_manifext_aidl_panelchaplin.xml',
        'etc/vintf/manifest/dvs-aidl-service.xml',
        'etc/vintf/manifest/manifest_oplus_cryptoeng.xml',
        'etc/vintf/manifest/manifest_oplus_charger_aidl.xml',
        'etc/vintf/manifest/manifest_touch_aidl.xml',
        'etc/vintf/manifest/manifest_oplus_camera_rfi.xml',
        'etc/vintf/manifest/manifest_oplus_face.xml',
        'etc/vintf/manifest/device_manifest_subsys.xml',
        'etc/vintf/manifest/binaural_record.xml',
        'etc/vintf/manifest/manifest_oplus_virtualdevice_audio_aidl.xml',
        'etc/vintf/manifest/manifest_oplus_sendextcamcmd.xml',
        'etc/permissions/android.hardware.context_hub.xml',
        'etc/permissions/android.hardware.sensor.dynamic.head_tracker.xml',
        'etc/permissions/android.hardware.sensor.light.xml',
        'etc/permissions/android.hardware.telephony.ims.xml',
        'etc/permissions/vendor-oplus-hardware-charger.xml',
        'etc/permissions/vendor-oplus-hardware-cryptoeng.xml',
        'etc/permissions/vendor-oplus-hardware-touch-V1.xml',
    ])
    disable_service(root / 'etc/init/vendor.oplus.hardware.displaypanelfeature-service.rc',
                    ['displaypanelfeature-service'])
    disable_service(root / 'etc/init/dvs-aidl-service.rc', ['dvs-aidl-service'])
    disable_service(root / 'etc/init/vendor.oplus.hardware.cryptoeng@1.0-service_FDE.rc',
                    ['hal_cryptoeng_oplus'])
    disable_service(root / 'etc/init/vendor.oplus.hardware.charger-V12-service.rc',
                    ['oplus_charger_hal_service'])
    disable_service(root / 'etc/init/vendor-oplus-hardware-touch-V2-service.rc',
                    ['vendor.touch-aidl-1'])
    disable_service(root / 'etc/init/init.nvram.rc', ['nvram_qmi', 'nvram_diag'])
    disable_service(root / 'etc/init/mdm_feature.rc', [
        'update_feature_map', 'read_feature_map', 'update_single_sim_config',
        'update_feature_link'])
    rc = root / 'etc/init/vendor_engineermode.rc'
    if rc.is_file():
        text = rc.read_text(encoding='utf-8')
        text = re.sub(r'^\s*exec\s+.*engineer_vendor_shell\.sh\s+addRadioFile\s*$\n?',
                      '', text, flags=re.M)
        rc.write_text(text, encoding='utf-8')


def patch_my_product(root):
    root = Path(root)
    props(root / 'build.prop', {
        'ro.sf.lcd_density': '240',
        'persist.miui.density_v2': '240',
        'ro.zygote': 'zygote64_32',
        'ro.product.brand': 'Huawei',
        'ro.product.manufacturer': 'Huawei',
        'ro.product.model': 'MateBook E Go',
        'ro.product.name': 'gaokun3',
        'ro.product.device': 'gaokun3',
        'ro.surface_flinger.supports_background_blur': '0',
        'persist.sys.background_blur_supported': 'false',
        'persist.sys.usb.config': 'adb',
        'persist.adb.tcp.port': '5555',
    })
    remove_paths(root, ['etc/permissions/android.hardware.sensor.light.xml'])
    # These are donor OTA/authentication markers, not hardware properties.
    p = root / 'build.prop'
    text = p.read_text(encoding='utf-8')
    lines = [x for x in text.splitlines()
             if not x.startswith(('ro.product.supported_versions=',
                                  'ro.product.authentication='))]
    p.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def patch_product(root):
    root = Path(root)
    xml = '''<?xml version="1.0" encoding="utf-8"?>
<displayConfiguration>
  <densityMapping><density><height>2560</height><width>1600</width><density>240</density></density></densityMapping>
  <screenBrightnessDefault>0.5</screenBrightnessDefault>
  <screenBrightnessMap>
    <point><value>0.0</value><nits>0.0</nits></point>
    <point><value>0.04</value><nits>20.0</nits></point>
    <point><value>1.0</value><nits>500.0</nits></point>
  </screenBrightnessMap>
</displayConfiguration>
'''
    write_text(root / 'etc/displayconfig/default.xml', xml)
    write_text(root / 'etc/displayconfig/display_id_0.xml', xml)


def patch_system_ext(root):
    remove_paths(root, [
        'priv-app/ims',
        'app/ImsDataChannelService',
        'app/OTA',
        'bin/cotad',
        'bin/imsvtdaemon',
        'etc/init/cotad.rc',
        'etc/init/imsvtdaemon.rc',
        'etc/permissions/vendor.qti.imsdatachannel.xml',
        'etc/permissions/vendor.qti.imsdcservice.xml',
    ])


def patch_my_stock(root):
    remove_paths(root, [
        'priv-app/OplusBootReg',
        'priv-app/Cota',
        'app/RomUpdate',
    ])


def main():
    if len(sys.argv) != 3:
        raise SystemExit('usage: v43_edit_tree.py STAGE ROOT')
    stage, root = sys.argv[1], sys.argv[2]
    {'system': patch_system, 'vendor': patch_vendor, 'odm': patch_odm,
     'my_product': patch_my_product, 'product': patch_product,
     'system_ext': patch_system_ext, 'my_stock': patch_my_stock}[stage](root)
    print('patched', stage, root)


if __name__ == '__main__':
    main()
