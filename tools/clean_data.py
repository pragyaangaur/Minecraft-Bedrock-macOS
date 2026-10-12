"""Undo the start-up state that the memory dump left in .data.

Usage: .venv/bin/python -I tools/clean_data.py <loadable.exe> <dump.dmp> <out.exe>

The dump was taken at the title screen, so the CRT believes its static
constructors already ran and globals point into the PC's heap. This resets:

1. __scrt_current_native_startup_state, found by following the entry point to
   __scrt_common_main_seh and reading its `mov ecx, [rip+x]; cmp ecx, 1`.
2. _Init_global_epoch for thread-safe statics, back to INT_MIN. It is found
   from _Init_thread_footer, which is the only code doing
   `inc eax; mov [rip+epoch], eax; mov [rbx], eax`. The guards themselves
   are zero-filled .bss and were never in the dumped file.
3. Every qword in .data that points into memory the dump captured outside the
   image itself (heap, stacks, other modules). Static initialisers cannot
   produce such pointers, so they were written at run time. They become null.
   When the nulled pointer heads an MSVC std::string or std::wstring (size
   and capacity follow at +16 and +24, capacity at least 8), the string is
   made a valid empty one: size 0, capacity 7, which is the small-buffer form
   for both. Under C++20 an empty global string has no constructor to redo it.

Counters and flags that the game changed at run time cannot be told apart from
initial values and are left alone.
"""
import re
import struct
import sys
from bisect import bisect_right

import capstone
import pefile

MEMORY64_LIST = 9
INT_MIN = -2**31


def dump_ranges(path):
    with open(path, "rb") as f:
        _, _, count, rva = struct.unpack("<4sIII", f.read(16))
        f.seek(rva)
        table = {t: r for t, _, r in struct.iter_unpack("<III", f.read(12 * count))}
        f.seek(table[MEMORY64_LIST])
        n, _ = struct.unpack("<QQ", f.read(16))
        ranges = sorted(struct.iter_unpack("<QQ", f.read(16 * n)))
    return [r[0] for r in ranges], ranges


def disasm(pe, rva, size):
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    md.detail = True
    base = pe.OPTIONAL_HEADER.ImageBase
    return list(md.disasm(pe.get_data(rva, size), base + rva))


def startup_state_rva(pe):
    base = pe.OPTIONAL_HEADER.ImageBase
    entry = disasm(pe, pe.OPTIONAL_HEADER.AddressOfEntryPoint, 0x20)
    jmp = next(i for i in entry if i.mnemonic == "jmp")
    body = disasm(pe, jmp.operands[0].imm - base, 0x80)
    for a, b in zip(body, body[1:]):
        if a.mnemonic == "mov" and a.op_str.startswith("ecx, dword ptr [rip") and b.op_str == "ecx, 1":
            return a.address + a.size + a.operands[1].mem.disp - base
    sys.exit("could not find __scrt_current_native_startup_state")


def epoch_rva(pe):
    text = pe.sections[0]
    code = pe.get_data(text.VirtualAddress, text.SizeOfRawData)
    hits = [m.start() for m in re.finditer(rb"\xff\xc0\x89\x05(?s:....)\x89\x03", code)]
    if len(hits) != 1:
        sys.exit(f"expected one _Init_thread_footer, found {len(hits)}")
    (disp,) = struct.unpack_from("<i", code, hits[0] + 4)
    return text.VirtualAddress + hits[0] + 8 + disp


def main():
    src, dump, dest = sys.argv[1:4]
    pe = pefile.PE(src, fast_load=True)
    base, size = pe.OPTIONAL_HEADER.ImageBase, pe.OPTIONAL_HEADER.SizeOfImage
    data = next(s for s in pe.sections if s.Name.rstrip(b"\0") == b".data")
    va, raw = data.VirtualAddress, data.SizeOfRawData
    buf = bytearray(pe.get_data(va, raw))

    state = startup_state_rva(pe)
    print(f"startup state at {state:#x} was {struct.unpack_from('<i', buf, state - va)[0]}, now 0")
    struct.pack_into("<i", buf, state - va, 0)

    epoch = epoch_rva(pe)
    v = struct.unpack_from("<i", buf, epoch - va)[0]
    print(f"_Init_global_epoch at {epoch:#x} was INT_MIN+{v - INT_MIN}, now INT_MIN")
    struct.pack_into("<i", buf, epoch - va, INT_MIN)

    starts, ranges = dump_ranges(dump)
    nulled = strings = 0
    for o in range(0, raw - 7, 8):
        (p,) = struct.unpack_from("<Q", buf, o)
        if p < 0x10000 or base <= p < base + size:
            continue
        i = bisect_right(starts, p) - 1
        if i >= 0 and p < ranges[i][0] + ranges[i][1]:
            struct.pack_into("<Q", buf, o, 0)
            nulled += 1
            if o + 32 <= raw:
                length, capacity = struct.unpack_from("<QQ", buf, o + 16)
                if 8 <= capacity < 1 << 40 and length <= capacity:
                    struct.pack_into("<QQQQ", buf, o, 0, 0, 0, 7)
                    strings += 1
    print(f"nulled {nulled} run-time pointers in .data, {strings} of them heading strings now empty")

    pe.set_bytes_at_rva(va, bytes(buf))
    pe.OPTIONAL_HEADER.CheckSum = 0
    pe.OPTIONAL_HEADER.CheckSum = pe.generate_checksum()
    pe.write(dest)
    print(f"wrote {dest}")


if __name__ == "__main__":
    main()
