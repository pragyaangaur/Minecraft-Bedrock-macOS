# Extra hooks for tools/trace/trace_patch.py. These follow the persona skin registrar.
HOOKS = [
    (10, 0x4758c70, ["push rbp", "push r15", "push r14"], 5, None),           # registrar entry, rdx = profile
    (8, 0x4758cce, None, 9, ("testje", 0x47595e2, 0x4758cd7)),               # after pack lookup, rax = pack
    (9, 0x1432450, ["push rbp", "push rsi", "sub rsp, 0x38"], 6, None),      # replace slot: rcx pack, r8 index
]
