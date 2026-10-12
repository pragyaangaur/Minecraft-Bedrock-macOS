"""Turn the executable rebuilt from a memory dump back into something a loader accepts.

Usage: .venv/bin/python -I tools/make_loadable.py <in.exe> <out.exe>

The Windows loader wrote addresses from the PC into the image, so this undoes
those writes:

- Every IAT slot is copied back from the import name table.
- The Control Flow Guard check and dispatch pointers in the load config point
  at ntdll on the PC. They go back to what the linker emits when CFG is off at
  run time: a `ret` for the check functions and a `jmp rax` for the dispatch
  functions. Any C3 or FF E0 bytes in .text will do, since the pointer is
  jumped to directly and instruction boundaries do not matter.
- The signature directory is cleared because it points at file bytes that the
  dump never had.

ImageBase already equals the address the image was loaded at, which keeps the
base relocations consistent. The .data section is handled by clean_data.py.
"""
import struct
import sys

import pefile

CHECK = ("GuardCFCheckFunctionPointer", "GuardXFGCheckFunctionPointer")
DISPATCH = ("GuardCFDispatchFunctionPointer", "GuardXFGDispatchFunctionPointer",
            "GuardXFGTableDispatchFunctionPointer")


def stub(pe, body):
    """RVA of the first occurrence of `body` in .text."""
    text = pe.sections[0]
    return text.VirtualAddress + pe.get_data(text.VirtualAddress, text.SizeOfRawData).index(body)


def main():
    src, dest = sys.argv[1:3]
    pe = pefile.PE(src, fast_load=True)
    base = pe.OPTIONAL_HEADER.ImageBase
    pe.parse_data_directories(directories=[
        pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"],
        pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_LOAD_CONFIG"],
    ])

    patches = {}
    for entry in pe.DIRECTORY_ENTRY_IMPORT:
        d = entry.struct
        k = 0
        while name_thunk := pe.get_qword_at_rva(d.OriginalFirstThunk + 8 * k):
            patches[d.FirstThunk + 8 * k] = name_thunk
            k += 1
    print(f"restoring {len(patches)} IAT slots")

    lc = pe.DIRECTORY_ENTRY_LOAD_CONFIG.struct
    ret, jmp_rax = base + stub(pe, b"\xc3"), base + stub(pe, b"\xff\xe0")
    for names, target in ((CHECK, ret), (DISPATCH, jmp_rax)):
        for name in names:
            slot = getattr(lc, name, 0)
            if slot:
                print(f"{name}: {pe.get_qword_at_rva(slot - base):#x} -> {target:#x}")
                patches[slot - base] = target

    for name in ("IMAGE_DIRECTORY_ENTRY_SECURITY", "IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT"):
        dd = pe.OPTIONAL_HEADER.DATA_DIRECTORY[pefile.DIRECTORY_ENTRY[name]]
        dd.VirtualAddress = dd.Size = 0

    # pefile writes its parsed thunks back over the IAT, so patch the serialised bytes.
    out = pefile.PE(data=pe.write(), fast_load=True)
    for rva, value in patches.items():
        off = out.get_offset_from_rva(rva)
        out.__data__[off:off + 8] = struct.pack("<Q", value)
    out.OPTIONAL_HEADER.CheckSum = 0
    out.OPTIONAL_HEADER.CheckSum = out.generate_checksum()
    out.write(dest)
    print(f"wrote {dest}")


if __name__ == "__main__":
    main()
