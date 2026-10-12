# Disassemble around each RVA, starting from the .pdata function that contains it.
# Usage: .venv/bin/python tools/dev/func.py build/game/Minecraft.Windows.exe <rva> [<rva> ...]
import sys, struct, bisect, pefile, capstone
pe=pefile.PE(sys.argv[1],fast_load=True); IB=pe.OPTIONAL_HEADER.ImageBase
dd=pe.OPTIONAL_HEADER.DATA_DIRECTORY[3]; raw=pe.get_data(dd.VirtualAddress,dd.Size)
fns=sorted(struct.iter_unpack("<III",raw)); starts=[f[0] for f in fns]
md=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64)
for a in sys.argv[2:]:
    rva=int(a,16); i=bisect.bisect_right(starts,rva)-1; b,e,u=fns[i]
    print(f"== {rva:#x} in func {b:#x}-{e:#x}")
    lo=max(b,rva-0x60)
    # disassemble from func start but print only near target
    for ins in md.disasm(pe.get_data(b,min(e,rva+0x20)-b),IB+b):
        r=ins.address-IB
        if r>=lo: print(f"{r:#x}: {ins.mnemonic} {ins.op_str}{'   <==' if r==rva else ''}")
