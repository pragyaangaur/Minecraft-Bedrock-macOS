# List the strings that the .pdata function around each RVA references through lea.
# Usage: .venv/bin/python tools/dev/strs.py build/game/Minecraft.Windows.exe <rva> [<rva> ...]
import sys, struct, bisect, re, pefile, capstone
pe=pefile.PE(sys.argv[1],fast_load=True); IB=pe.OPTIONAL_HEADER.ImageBase
dd=pe.OPTIONAL_HEADER.DATA_DIRECTORY[3]; raw=pe.get_data(dd.VirtualAddress,dd.Size)
fns=sorted(struct.iter_unpack("<III",raw)); starts=[f[0] for f in fns]
md=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64); md.detail=True
for a in sys.argv[2:]:
    rva=int(a,16); i=bisect.bisect_right(starts,rva)-1; b,e,u=fns[i]
    print(f"== func {b:#x}-{e:#x}")
    for ins in md.disasm(pe.get_data(b,e-b),IB+b):
        if ins.mnemonic=="lea" and "rip" in ins.op_str:
            t=ins.address+ins.size+ins.operands[1].mem.disp-IB
            try: d=pe.get_data(t,80)
            except Exception: continue
            m=re.match(rb"[\x20-\x7e]{4,}",d)
            if m: print(f"  {ins.address-IB:#x}: {m.group().decode()[:76]}")
