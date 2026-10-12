"""Pull one loaded module out of a full-memory Windows minidump and rebuild a PE file.

Usage: .venv/bin/python -I tools/extract_module.py <dump.dmp> <module name> <out.exe>

Writes <out.exe> in file layout (sections moved back to their raw offsets) and
<out.exe>.mem with the raw memory image. Pages missing from the dump are zeros.
"""
import struct
import sys

import pefile

MODULE_LIST, MEMORY64_LIST = 4, 9


def streams(f):
    f.seek(0)
    sig, _, count, rva = struct.unpack("<4sIII", f.read(16))
    if sig != b"MDMP":
        sys.exit("not a minidump")
    f.seek(rva)
    table = f.read(12 * count)
    return {t: (size, r) for t, size, r in struct.iter_unpack("<III", table)}


def find_module(f, rva, name):
    f.seek(rva)
    (count,) = struct.unpack("<I", f.read(4))
    entries = f.read(108 * count)
    for i in range(count):
        base, size = struct.unpack_from("<QI", entries, 108 * i)
        (name_rva,) = struct.unpack_from("<I", entries, 108 * i + 20)
        f.seek(name_rva)
        (length,) = struct.unpack("<I", f.read(4))
        path = f.read(length).decode("utf-16le")
        if path.lower().endswith("\\" + name.lower()):
            return base, size, path
    sys.exit(f"module {name} not in dump")


def read_image(f, rva, base, size):
    f.seek(rva)
    count, data_rva = struct.unpack("<QQ", f.read(16))
    ranges = list(struct.iter_unpack("<QQ", f.read(16 * count)))
    image = bytearray(size)
    covered = 0
    offset = data_rva
    for start, length in ranges:
        lo, hi = max(start, base), min(start + length, base + size)
        if lo < hi:
            f.seek(offset + (lo - start))
            image[lo - base:hi - base] = f.read(hi - lo)
            covered += hi - lo
        offset += length
    return image, covered


def unmap(image):
    pe = pefile.PE(data=bytes(image), fast_load=True)
    end = max(s.PointerToRawData + s.SizeOfRawData for s in pe.sections)
    out = bytearray(end)
    hdr = pe.OPTIONAL_HEADER.SizeOfHeaders
    out[:hdr] = image[:hdr]
    for s in pe.sections:
        raw = s.SizeOfRawData
        out[s.PointerToRawData:s.PointerToRawData + raw] = image[s.VirtualAddress:s.VirtualAddress + raw]
    return out, pe


def main():
    dump, name, dest = sys.argv[1:4]
    with open(dump, "rb") as f:
        table = streams(f)
        if MEMORY64_LIST not in table:
            sys.exit("dump has no full memory (Memory64List missing)")
        base, size, path = find_module(f, table[MODULE_LIST][1], name)
        image, covered = read_image(f, table[MEMORY64_LIST][1], base, size)
    print(f"{path}\nbase {base:#x}, size {size:,}, captured {covered:,} ({100 * covered / size:.1f}%)")
    print("header:", image[:2])
    open(dest + ".mem", "wb").write(image)
    out, pe = unmap(image)
    open(dest, "wb").write(out)
    print(f"wrote {dest} ({len(out):,} bytes), {len(pe.sections)} sections:")
    for s in pe.sections:
        print(f"  {s.Name.rstrip(b'\\0').decode():10} va {s.VirtualAddress:#10x} raw {s.SizeOfRawData:>12,}")


if __name__ == "__main__":
    main()
