# Static analysis helper for the rebuilt executable. The first import writes
# build/dev/img.bin (the image in its virtual layout, about 300 MB) and later
# imports just read it.
# Use: cd tools/dev && ../../.venv/bin/python -c "from img import *; fdis(0x140d960)"
# dis(rva, n) disassembles n instructions, fdis(rva) the whole .pdata function around rva,
# callers(rva) finds direct call sites, riprefs(rva) finds rip-relative references,
# q()/d() read 8/4 bytes, func(rva) gives the .pdata bounds. All addresses are RVAs.
import os, sys, struct, bisect, re, mmap
import numpy as np, capstone
EXE=os.path.join(os.path.dirname(os.path.abspath(__file__)),"../../build/game/Minecraft.Windows.exe")
H=os.path.dirname(os.path.abspath(__file__)); BIN=os.path.join(H,"../../build/dev/img.bin"); IB=0x7ff6b18a0000
if not os.path.exists(BIN):
    import pefile
    pe=pefile.PE(EXE,fast_load=True); img=bytearray(pe.OPTIONAL_HEADER.SizeOfImage)
    raw=open(EXE,'rb').read(); img[:0x1000]=raw[:0x1000]
    for s in pe.sections:
        n=min(s.SizeOfRawData,s.Misc_VirtualSize); img[s.VirtualAddress:s.VirtualAddress+n]=raw[s.PointerToRawData:s.PointerToRawData+n]
    os.makedirs(os.path.dirname(BIN),exist_ok=True); open(BIN,'wb').write(img)
M=open(BIN,'rb').read()
PD=np.frombuffer(M[0x12038000:0x12038000+0xacef60],dtype='<u4').reshape(-1,3); STARTS=PD[:,0]
md=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64); md.detail=True
def q(r): return struct.unpack_from('<Q',M,r)[0]
def d(r): return struct.unpack_from('<I',M,r)[0]
def func(r):
    i=int(np.searchsorted(STARTS,r,'right'))-1; return int(PD[i,0]),int(PD[i,1])
def dis(r,n=60,stop=True):
    for k,i in enumerate(md.disasm(M[r:r+n*15],IB+r)):
        if k>=n: break
        a=i.address-IB; extra=''
        if 'rip' in i.op_str:
            for o in i.operands:
                if o.type==capstone.x86.X86_OP_MEM and o.mem.base==capstone.x86.X86_REG_RIP:
                    t=i.address+i.size+o.mem.disp-IB; s=re.match(rb'[\x20-\x7e]{4,}',M[t:t+80]) if t<len(M) else None
                    extra=f'  ; {t:#x}'+(f' "{s.group().decode()[:60]}"' if s else '')
        elif i.mnemonic in('call','jmp') and i.op_str.startswith('0x'): extra=f'  ; {int(i.op_str,16)-IB:#x}'
        print(f'{a:#x}: {i.mnemonic} {i.op_str}{extra}')
        if stop and i.mnemonic in('int3',) : break
def fdis(r):
    b,e=func(r); print(f'== func {b:#x}-{e:#x}'); [print(x) for x in lines(b,e)]
def lines(b,e):
    out=[]
    import io,contextlib
    f=io.StringIO()
    with contextlib.redirect_stdout(f): dis(b,(e-b),False)
    for l in f.getvalue().splitlines():
        if int(l.split(':')[0],16)<e: out.append(l)
    return out
TEXT=np.frombuffer(M[0x1000:0x1000+0xe5a5bf6],dtype=np.uint8)
def callers(t):
    # E8 rel32 scan
    idx=np.nonzero(TEXT[:-5]==0xE8)[0]
    res=[]
    r=(TEXT[idx+1].astype(np.int64)|(TEXT[idx+2].astype(np.int64)<<8)|(TEXT[idx+3].astype(np.int64)<<16)|(TEXT[idx+4].astype(np.int64)<<24))
    r=np.where(r>=2**31,r-2**32,r); tgt=idx+0x1000+5+r
    return [int(x)+0x1000 for x in idx[tgt==t]]
def riprefs(t):
    # any instruction with disp32 pointing to t (approx: scan all 4-byte windows)
    out=[]
    a=np.frombuffer(M[0x1000:0x1000+0xe5a5bf6],dtype=np.uint8).astype(np.int64)
    v=a[:-4]|(a[1:-3]<<8)|(a[2:-2]<<16)|(a[3:-1]<<24); v=np.where(v>=2**31,v-2**32,v)
    pos=np.arange(len(v))+0x1000
    for tail in range(4,9):
        hit=np.nonzero(pos+tail+v==t)[0]
        out+= [int(h)+0x1000 for h in hit]
    return sorted(set(out))
