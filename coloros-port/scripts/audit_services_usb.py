#!/usr/bin/env python3
from pathlib import Path
import zipfile
jar = Path('/home/cenmin/v25-system/tree/system/framework/services.jar')
with zipfile.ZipFile(jar) as z:
    print('jar_entries', len(z.namelist()))
    for name in z.namelist():
        if not name.endswith('.dex'):
            continue
        data = z.read(name)
        for needle in [b'/sys/class/android_usb', b'/sys/class/udc']:
            print(name, needle.decode(), data.count(needle))