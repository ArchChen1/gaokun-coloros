import re
from pathlib import Path

root = Path('/home/cenmin/coloros-trees-xattr')
context_files = [
    root/'system/system/etc/selinux/plat_property_contexts',
    root/'system_ext/etc/selinux/system_ext_property_contexts',
    root/'product/etc/selinux/product_property_contexts',
    root/'vendor/etc/selinux/vendor_property_contexts',
]
# Build defined types from CIL files only.
type_defs = set()
cil_files = []
for base in (root/'system/system/etc/selinux', root/'system_ext/etc/selinux',
             root/'product/etc/selinux', root/'vendor/etc/selinux', root/'odm/etc/selinux'):
    if base.is_dir():
        for p in base.rglob('*.cil'):
            cil_files.append(p)
            text = p.read_text(errors='replace')
            for m in re.finditer(r'\(type(?:attributeset)?\s+([A-Za-z0-9_.:-]+)', text):
                type_defs.add(m.group(1))
print('CIL files', len(cil_files), 'types', len(type_defs))
for cf in context_files:
    if not cf.is_file():
        continue
    missing = {}
    for lineno, line in enumerate(cf.read_text(errors='replace').splitlines(), 1):
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        parts = s.split()
        if len(parts) < 2:
            continue
        m = re.search(r'u:object_r:([A-Za-z0-9_.:-]+):s0', parts[1])
        if not m:
            continue
        t = m.group(1)
        if t not in type_defs:
            missing.setdefault(t, []).append((lineno, s))
    print('====', cf)
    print('missing types', len(missing))
    for t, rows in sorted(missing.items()):
        print('TYPE', t, 'count', len(rows))
        for lineno, s in rows[:5]:
            print(' ', lineno, s)
        if len(rows) > 5:
            print('  ...')
