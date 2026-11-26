#!/usr/bin/env python3
"""把 libcodec2_vndk.so 里 GraphicBufferMapper::setSmpte2094_5 的未定义引用改成 WEAK。

背景（docs/HW-CODEC2.md 第 7 节）：
  vendor 链接命名空间的搜索顺序是 /odm/lib64 → /vendor/lib64，
  ColorOS 自带的 /odm/lib64/libui.so 比 crDroid 编的那份旧，没有 setSmpte2094_5，
  于是 C2 HAL 一起来就 CANNOT LINK，init.svc 一直 restarting。

为什么改 WEAK 而不是别的：
  - 不动 odm 的 libui：那份被显示/相机的 vendor HAL 共用，换掉风险不可控；
  - 整个 C2 闭包只缺这 1 个符号（已逐库核对）；
  - 该符号在 libcodec2_vndk 里只有 1 处调用，位于内部 HDR 动态元数据写入路径，
    而三个 v4l2 组件库不引用任何 Smpte2094 符号 —— 这条路走不到；
  - bionic 对未解析的 WEAK 符号放行（GOT 置 0），对 GLOBAL 才报 cannot locate symbol。

只改 .dynsym 里那一条的 st_info 高 4 位（绑定 GLOBAL→WEAK），文件长度不变。
用法：patch_codec_libui_weak.py <libcodec2_vndk.so> [--check]
"""
import struct
import sys

SYM = ('_ZN7android19GraphicBufferMapper15setSmpte2094_50EPK13native_handle'
       'NSt3__18optionalINS4_6vectorIhNS4_9allocatorIhEEEEEE')
STB_GLOBAL, STB_WEAK = 1, 2


def sections(d):
    e_shoff = struct.unpack_from('<Q', d, 0x28)[0]
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from('<HHH', d, 0x3a)
    secs = []
    for i in range(e_shnum):
        o = e_shoff + i * e_shentsize
        nm, typ, flags, addr, off, size, link, info, align, entsize = struct.unpack_from('<IIQQQQIIQQ', d, o)
        secs.append(dict(nm=nm, off=off, size=size, link=link))
    st = secs[e_shstrndx]
    names = d[st['off']:st['off'] + st['size']]
    for s in secs:
        s['name'] = names[s['nm']:].split(b'\0')[0].decode()
    return secs


def find(d):
    secs = sections(d)
    ds = next(s for s in secs if s['name'] == '.dynsym')
    st = secs[ds['link']]
    strs = d[st['off']:st['off'] + st['size']]
    for i in range(ds['size'] // 24):
        o = ds['off'] + i * 24
        nm, info, other, shndx, val, size = struct.unpack_from('<IBBHQQ', d, o)
        if shndx == 0 and strs[nm:].split(b'\0')[0].decode() == SYM:
            return o + 4, info, i
    raise SystemExit('找不到目标未定义符号，这份库不是预期的那版')


def main():
    path = sys.argv[1]
    check = '--check' in sys.argv
    d = bytearray(open(path, 'rb').read())
    pos, info, idx = find(d)
    bind = info >> 4
    print('  dynsym[%d] st_info=0x%02x 绑定=%d' % (idx, info, bind))
    if bind == STB_WEAK:
        print('  已是 WEAK，跳过')
        return
    if bind != STB_GLOBAL:
        raise SystemExit('绑定既不是 GLOBAL 也不是 WEAK，停')
    if check:
        print('  --check：需要改成 WEAK，未写入')
        return
    new = (STB_WEAK << 4) | (info & 0xF)
    before = bytes(d)
    d[pos] = new
    open(path, 'wb').write(d)
    after = open(path, 'rb').read()
    assert len(after) == len(before), '文件长度变了'
    diff = [i for i in range(len(after)) if after[i] != before[i]]
    assert diff == [pos], ('改动不止 1 字节', diff[:10])
    print('  已改为 WEAK（st_info=0x%02x），只动 1 字节，长度 %d B 不变' % (new, len(after)))


if __name__ == '__main__':
    main()