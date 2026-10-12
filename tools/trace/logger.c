/* Trace logger, called from the detours that tools/trace/trace_patch.py writes. Freestanding. */
typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned char u8;
/* register block pushed by the detour, lowest address first */
struct regs { u64 r15, r14, r13, r12, r11, r10, r9, r8, rdi, rsi, rbp, rbx, rdx, rcx, rax, flags; };

static char *put(char *p, const char *s) { while (*s) *p++ = *s++; return p; }
static char *hex(char *p, u64 v) {
    static const char d[] = "0123456789abcdef";
    *p++ = '0'; *p++ = 'x';
    int started = 0;
    for (int i = 60; i >= 0; i -= 4) { int n = (v >> i) & 15; if (n || started || i == 0) { *p++ = d[n]; started = 1; } }
    return p;
}
static int ok(u64 p) { return p >= 0x10000 && p < 0x7fffffff0000ULL; }
static char *bytes(char *p, u64 a, int n) {
    static const char d[] = "0123456789abcdef";
    if (!ok(a)) return put(p, "?");
    for (int i = 0; i < n; i++) { u8 b = ((u8 *)a)[i]; *p++ = d[b >> 4]; *p++ = d[b & 15]; }
    return p;
}
static char *kv(char *p, const char *k, u64 v) { p = put(p, " "); p = put(p, k); p = put(p, "="); return hex(p, v); }
static u64 rd(u64 a, u64 off) { return ok(a) && ok(a + off) ? *(u64 *)(a + off) : 0xdead; }
static u32 rd32(u64 a, u64 off) { return ok(a) && ok(a + off) ? *(u32 *)(a + off) : 0xdead; }

__attribute__((section(".text$zz"))) void logger(u32 id, struct regs *r) {
    char buf[1100];
    char *p = buf;
    p = put(p, "trace id="); p = hex(p, id);
    switch (id) {
    case 1: {  /* entry of 0x140d960: rcx=this, dl=flag */
        u64 th = r->rcx, p8 = rd(th, 8), vt = rd(p8, 0);
        p = kv(p, "this", th); p = kv(p, "flag", r->rdx & 0xff); p = kv(p, "p8", p8); p = kv(p, "vt", vt);
        p = kv(p, "vt_d8", rd(vt, 0xd8)); p = kv(p, "vt_d0", rd(vt, 0xd0)); p = kv(p, "vt_c8", rd(vt, 0xc8));
        p = put(p, " uuid108="); p = bytes(p, th + 0x108, 16);
        p = put(p, " uuid118="); p = bytes(p, th + 0x118, 16);
        p = kv(p, "vt_this", rd(th, 0)); p = kv(p, "G0", rd(0x7ff6b18a0000ULL + 0x11d325b0, 0)); p = kv(p, "G1", rd(0x7ff6b18a0000ULL + 0x11d325b0, 8));
        p = kv(p, "ret", rd((u64)r + 16 * 8, 0));
        p = put(p, " thisdump=");
        for (int i = 0; i < 0x1c; i++) { p = hex(p, rd(th, 0x100 + i * 8)); p = put(p, ","); }
        p = put(p, " p8dump=");
        for (int i = 0; i < 16; i++) { p = hex(p, rd(p8, i * 8)); p = put(p, ","); }
        break; }
    case 2: {  /* after first +0xd8 lookup: rax=skin or null, rdi=this */
        p = kv(p, "res", r->rax); p = kv(p, "this", r->rdi); p = kv(p, "bl", r->rbx & 0xff);
        if (r->rax) { p = kv(p, "state1b8", rd32(r->rax, 0x1b8)); p = kv(p, "vt", rd(r->rax, 0)); }
        break; }
    case 3:   /* second lookup (+0xc8) result in al */
        p = kv(p, "ret_c8", r->rax & 0xff); p = kv(p, "skin", r->rbx); break;
    case 4:   /* rand result */
        p = kv(p, "rand", r->rax & 0xffffffff); p = kv(p, "idx", (r->rax & 0xffffffff) % 9); break;
    case 5: {  /* result of 0x140dcc0 (default pick) in rax */
        p = kv(p, "dflt", r->rax); p = put(p, " dflt_bytes="); p = bytes(p, r->rax, 48);
        p = put(p, " uuid108="); p = bytes(p, r->rdi + 0x108, 16); break; }
    case 6:   /* before 2nd +0xd8 call: UUID after resolve */
        p = kv(p, "this", r->rdi); p = put(p, " uuid108="); p = bytes(p, r->rdi + 0x108, 16); break;
    case 7: {  /* return value */
        p = kv(p, "final", r->rax);
        if (r->rax) { p = kv(p, "state1b8", rd32(r->rax, 0x1b8)); p = kv(p, "vt", rd(r->rax, 0)); }
        break; }
    case 10: {  /* registrar entry */
        u64 pr = r->rdx;
        p = kv(p, "profile", pr); p = kv(p, "type9c0", rd(pr, 0x9c0) & 0xff); p = kv(p, "f971", rd(pr, 0x971) & 0xff);
        p = kv(p, "idx9e4", rd32(pr, 0x9e4)); p = kv(p, "ret", rd((u64)r + 16 * 8, 0));
        break; }
    case 8: {  /* after persona pack lookup */
        u64 pk = r->rax, pr = r->rsi;
        p = kv(p, "pack", pk); p = kv(p, "type9c0", rd(pr, 0x9c0) & 0xff); p = kv(p, "f971", rd(pr, 0x971) & 0xff);
        p = kv(p, "idx9e4", rd32(pr, 0x9e4));
        if (pk) { u64 b = rd(pk, 0x88), e = rd(pk, 0x90); p = kv(p, "nslots", (e - b) / 0x228);
            for (int i = 0; i < 10 && b + i * 0x228 < e; i++) { p = kv(p, "slot", rd32(b + i * 0x228, 0x1e0)); } }
        break; }
    case 9: {  /* replace slot */
        u64 pk = r->rcx, b = rd(pk, 0x88), e = rd(pk, 0x90);
        p = kv(p, "pack", pk); p = kv(p, "index", r->r8 & 0xffffffff); p = kv(p, "nslots", (e - b) / 0x228);
        for (int i = 0; i < 10 && b + i * 0x228 < e; i++) { p = kv(p, "slot", rd32(b + i * 0x228, 0x1e0)); }
        p = kv(p, "ret", rd((u64)r + 16 * 8, 0));
        break; }
    default:
        p = kv(p, "rax", r->rax); p = kv(p, "rcx", r->rcx); p = kv(p, "rdx", r->rdx); p = kv(p, "rbx", r->rbx);
        p = kv(p, "rsi", r->rsi); p = kv(p, "rdi", r->rdi); p = kv(p, "r8", r->r8); p = kv(p, "r9", r->r9);
        break;
    }
    p = put(p, "\n"); *p = 0;
    (*(void (**)(const char *))IAT)(buf);
}
