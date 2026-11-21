#!/usr/bin/env python3
"""Inspect ColorOS APEX payloads for libutils VA-guard instruction patterns."""
from pathlib import Path
import subprocess, tempfile, zipfile, shutil, struct

APEX_DIR = Path('/home/cenmin/v25-system/tree/system/apex')
OUT = Path('/home/cenmin/apex-libutils-audit')
OUT.mkdir(exist_ok=True)
patterns = {
    'b2409be8': struct.pack('<I', 0xb2409be8),
    'b240bbe9': struct.pack('<I', 0xb240bbe9),
    'b240dfe0': struct.pack('<I', 0xb240dfe0),
}
print('apex_dir', APEX_DIR)
for apex in sorted(list(APEX_DIR.glob('*.apex')) + list(APEX_DIR.glob('*.capex'))):
    try:
        with zipfile.ZipFile(apex) as z:
            names = z.namelist()
            if 'original_apex' in names:
                data = z.read('original_apex')
                outer = OUT / (apex.name + '.original.apex')
                outer.write_bytes(data)
                with zipfile.ZipFile(outer) as z2:
                    payload = z2.read('apex_payload.img')
            elif 'apex_payload.img' in names:
                payload = z.read('apex_payload.img')
            else:
                continue
    except Exception as e:
        print('ERROR', apex.name, e)
        continue
    pimg = OUT / (apex.name + '.payload.img')
    pimg.write_bytes(payload)
    ftype = subprocess.check_output(['file', '-b', str(pimg)], text=True).strip()
    lib = None
    if 'EROFS' in ftype:
        ext = OUT / (apex.name + '.extract')
        shutil.rmtree(ext, ignore_errors=True)
        ext.mkdir()
        r = subprocess.run(['fsck.erofs', '--extract=' + str(ext), '--no-preserve', str(pimg)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode == 0:
            for candidate in [ext / 'lib64/libutils.so', ext / 'system/lib64/libutils.so']:
                if candidate.is_file():
                    lib = candidate
                    break
    elif 'ext' in ftype.lower():
        dest = OUT / (apex.name + '.libutils.so')
        r = subprocess.run(['debugfs', '-R', 'dump /lib64/libutils.so ' + str(dest), str(pimg)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode == 0 and dest.is_file():
            lib = dest
    if not lib:
        print('NO_LIBUTILS', apex.name, ftype[:60])
        continue
    data = lib.read_bytes()
    found = [name for name, needle in patterns.items() if needle in data]
    print('LIBUTILS', apex.name, lib.stat().st_size, 'patterns=' + ','.join(found) if found else 'patterns=none')