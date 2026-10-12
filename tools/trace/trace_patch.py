"""Build a logging copy of the rebuilt executable.

Usage: .venv/bin/python -I tools/trace/trace_patch.py
Reads build/game/Minecraft.Windows.exe and writes build/game/Minecraft.Windows.trace.exe.

Each hook replaces a few instructions at a chosen RVA with a jump to a detour.
The detours are assembly generated here plus a freestanding C logger
(tools/trace/logger.c). They are linked with lld at a fixed address and
appended to the executable as a new section, ".trc". A detour saves every
register and the flags, calls the logger on an aligned stack, restores
everything, replays the replaced instructions and jumps back. The logger
formats one line and passes it to OutputDebugStringA through the executable's
own import slot, so it shows up in Wine's +seh log. Run it with:
  EXE=build/game/Minecraft.Windows.trace.exe TAG=trace tools/run_wine.sh '+seh' 150
and search the log for "trace id=".

The hooks follow the skin lookup in the skin manager (0x140d960).
"""
import struct, subprocess, sys, os, pefile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "build/game/Minecraft.Windows.exe")
DST = os.path.join(ROOT, "build/game/Minecraft.Windows.trace.exe")
OUT = os.path.join(ROOT, "build/trace")
CLANG = os.path.join(os.environ.get("HOMEBREW_PREFIX", "/opt/homebrew"), "opt/llvm/bin/clang")
IB = 0x7ff6b18a0000
NEWVA = 0x12c10000           # RVA of the new section
IAT_ODS = 0xf102c08          # RVA of OutputDebugStringA's import slot
STRIDE = 0x100

# (id, site RVA, stolen instructions (Intel syntax, position independent), stolen byte count, extra tail)
# tail "plain" = replay stolen then jmp site+len.  "testje" = test rax,rax / je 0x140d9e0 / jmp 0x140d99d
HOOKS = [
    (1, 0x140d960, ["push rbp", "push rsi", "push rdi", "push rbx", "sub rsp, 0x68"], 8, None),
    (2, 0x140d998, None, 9, ("testje", 0x140d9e0, 0x140d99d)),
    (3, 0x140d9d3, ["mov ecx, eax", "mov rax, rbx"], 5, None),
    (4, 0x140da1d, ["mov ecx, eax", "imul rcx, rcx, 0x38e38e39"], 9, None),
    (5, 0x140da39, ["mov qword ptr [rbp - 8], 0"], 8, None),
    (6, 0x140da53, ["mov rcx, qword ptr [rdi + 8]", "mov rax, qword ptr [rcx]"], 7, None),
    (7, 0x140da6a, ["nop", "add rsp, 0x68"], 5, None),
]

PRO = """
  pushfq
  push rax
  push rcx
  push rdx
  push rbx
  push rbp
  push rsi
  push rdi
  push r8
  push r9
  push r10
  push r11
  push r12
  push r13
  push r14
  push r15
  mov rbx, rsp
  sub rsp, 0x40
  and rsp, -16
  mov ecx, {id}
  mov rdx, rbx
  call logger
  mov rsp, rbx
  pop r15
  pop r14
  pop r13
  pop r12
  pop r11
  pop r10
  pop r9
  pop r8
  pop rdi
  pop rsi
  pop rbp
  pop rbx
  pop rdx
  pop rcx
  pop rax
  popfq
"""

def gen_asm():
    out = ['.intel_syntax noprefix', '.section .text$aa,"xr"']
    for i, (hid, site, stolen, n, tail) in enumerate(HOOKS):
        base = IB + NEWVA + 0x1000 * 0 + i * STRIDE   # section start address (+ i*stride)
        out.append(".balign 256\nhook%d:" % i)
        out.append(PRO.format(id=hid))
        if tail and tail[0] == "testje":
            _, je_t, ft = tail
            out.append("  test rax, rax")
            out.append("  je 2f\n  jmp 3f\n2: jmp hook%d + %d\n3: jmp hook%d + %d" % (i, IB + je_t - base, i, IB + ft - base))
            # note: je 2f / jmp 3f / 2: jmp je_t / 3: jmp fallthrough
        else:
            for ins in stolen:
                out.append("  " + ins)
            out.append("  jmp hook%d + %d" % (i, IB + site + n - base))
    return "\n".join(out) + "\n"

def main():
    os.makedirs(OUT, exist_ok=True)
    asm = os.path.join(OUT, "hooks.s")
    open(asm, "w").write(gen_asm())
    dll = os.path.join(OUT, "trace.dll")
    subprocess.check_call([CLANG, "--target=x86_64-pc-windows-msvc", "-O1", "-ffreestanding", "-fno-stack-protector",
        "-nostdlib", "-fuse-ld=lld", "-shared", "-Wl,/noentry", "-Wl,/nodefaultlib", "-Wl,/fixed",
        "-Wl,/base:%#x" % (IB + NEWVA - 0x10000), "-Wl,/align:65536", "-DIAT=%#xULL" % (IB + IAT_ODS),
        "-o", dll, asm, os.path.join(HERE, "logger.c")])
    t = pefile.PE(dll, fast_load=True)
    # whole image from 0x10000 (code, rodata and data of the logger) becomes one RWX section
    assert t.sections[0].VirtualAddress == 0x10000
    end = max(s.VirtualAddress + max(s.Misc_VirtualSize, s.SizeOfRawData) for s in t.sections)
    blob = bytearray(end - 0x10000)
    for s in t.sections:
        d = s.get_data()
        blob[s.VirtualAddress - 0x10000:s.VirtualAddress - 0x10000 + len(d)] = d
    text = t.sections[0]
    blob_va = IB + NEWVA
    assert t.OPTIONAL_HEADER.ImageBase + text.VirtualAddress == blob_va, hex(t.OPTIONAL_HEADER.ImageBase)
    data = bytearray(open(SRC, "rb").read())
    pe = pefile.PE(SRC, fast_load=True)
    lastsec = pe.sections[-1]
    rawsz = (len(blob) + 0x1ff) & ~0x1ff
    vsz = len(blob)
    rawoff = (len(data) + 0x1ff) & ~0x1ff
    data += b"\0" * (rawoff - len(data))
    data += bytes(blob) + b"\0" * (rawsz - len(blob))
    nsec = pe.FILE_HEADER.NumberOfSections
    sh_off = pe.DOS_HEADER.e_lfanew + 4 + 20 + pe.FILE_HEADER.SizeOfOptionalHeader + nsec * 40
    assert sh_off + 40 <= 0x400 and not any(data[sh_off:sh_off + 40])
    data[sh_off:sh_off + 40] = struct.pack("<8sIIIIIIHHI", b".trc", vsz, NEWVA, rawsz, rawoff, 0, 0, 0, 0, 0xE0000060)
    struct.pack_into("<H", data, pe.DOS_HEADER.e_lfanew + 6, nsec + 1)
    opt = pe.DOS_HEADER.e_lfanew + 24
    soi = (NEWVA + vsz + 0xfff) & ~0xfff
    struct.pack_into("<I", data, opt + 56, soi)
    struct.pack_into("<I", data, opt + 64, 0)  # checksum
    for i, (hid, site, stolen, n, tail) in enumerate(HOOKS):
        # file offset of site: it lies in .text (VA 0x1000 -> raw 0x400)
        s = [s for s in pe.sections if s.VirtualAddress <= site < s.VirtualAddress + s.SizeOfRawData][0]
        off = site - s.VirtualAddress + s.PointerToRawData
        tgt = NEWVA + i * STRIDE
        patch = b"\xe9" + struct.pack("<i", tgt - (site + 5)) + b"\x90" * (n - 5)
        data[off:off + n] = patch
        print("hook %d id %d site %#x -> %#x" % (i, hid, site, tgt))
    open(DST, "wb").write(data)
    print("wrote", DST)

main()
