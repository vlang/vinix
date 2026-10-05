# V stack protector

`python3 run.py` links the actual V guard and failure handler to independent C
callers built with global `-fstack-protector-strong`. It checks the guard's static
placeholder, 1,000 successful replacements and protected-frame returns, then
requires the V panic path when a child's guard is deliberately changed under
a protected frame. This introduces no out-of-bounds access. Privileged boot
entropy and the fatal panic are host adapters.

The test also rejects allocator imports and checks the generated LLVM attributes
to ensure initialization and its C ABI wrapper remain unprotected. The production
kernel uses the same attribute-bearing declarations in `stack_protector.h`.
Architecture entropy instructions additionally require both kernel builds and
guest boots; host tests cannot access ARM privileged identification registers.

`python3 diagnostic.py` tests both real V serial adapters through mocked byte
outputs under ASan/UBSan. Independent C callers check borrowed NUL-terminated
messages and 2,003 hexadecimal fault records against `snprintf`, including
zero, all-one and high-bit values. Allocator imports are rejected. The actual
fault probes and recovery labels live in architecture assembly files and are
exercised by the opt-in kernel-stack-guards QEMU fixtures.
