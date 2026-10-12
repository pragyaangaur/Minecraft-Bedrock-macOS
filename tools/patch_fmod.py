"""Guard FMOD's mixer against a zero channel count.

Usage: .venv/bin/python -I tools/patch_fmod.py game/fmod.dll game/fmod.guarded.dll

Under Wine the game crashes in about half of runs with a divide by zero at
fmod.dll RVA 0x1a52f (`idiv r15d`, r15 = 2 * channels). FMOD's loader publishes
a fresh, not yet filled entry array while the mixer still thinks the old one is
ready, so the mixer reads channels = 0. This redirects the 14 bytes at 0x1a524
to a stub in the unused tail of .text that returns 0 (nothing mixed, the same
exit FMOD takes at 0x1a5ff) when channels <= 0 and otherwise does the original
division. The output is for this Mac only and must not be shared.
"""
import struct
import sys

import capstone
import pefile

SITE, RESUME, NOTHING = 0x1a524, 0x1a532, 0x1a5ff
ORIGINAL = bytes.fromhex("4c637204 8bc6 99 478d3c36 41f7ff".replace(" ", ""))


def jmp(src, dst):
    return b"\xe9" + struct.pack("<i", dst - (src + 5))


def main():
    src, dest = sys.argv[1:3]
    pe = pefile.PE(src, fast_load=True)
    text = pe.sections[0]
    if pe.get_data(SITE, len(ORIGINAL)) != ORIGINAL:
        sys.exit("unexpected bytes at the divide; is this the same fmod.dll?")
    cave = text.VirtualAddress + text.Misc_VirtualSize
    cave = (cave + 15) & ~15
    stub = bytes.fromhex("4c637204 4585f6 7e0f 8bc6 99 478d3c36 41f7ff".replace(" ", ""))
    stub += jmp(cave + len(stub), RESUME)
    assert len(stub) == 24
    stub += jmp(cave + len(stub), NOTHING)
    end = cave + len(stub)
    if end > text.VirtualAddress + text.SizeOfRawData or any(pe.get_data(cave, len(stub))):
        sys.exit("no room for the stub in the tail of .text")
    patch = jmp(SITE, cave) + b"\x90" * (RESUME - SITE - 5)
    pe.set_bytes_at_rva(cave, stub)
    pe.set_bytes_at_rva(SITE, patch)
    text.Misc_VirtualSize = end - text.VirtualAddress
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)
    for rva, size in ((SITE, len(patch)), (cave, len(stub))):
        for i in md.disasm(pe.get_data(rva, size), rva):
            print(f"{i.address:#x} {i.mnemonic} {i.op_str}")
    pe.OPTIONAL_HEADER.CheckSum = 0
    pe.OPTIONAL_HEADER.CheckSum = pe.generate_checksum()
    pe.write(dest)
    print(f"wrote {dest}")


if __name__ == "__main__":
    main()
