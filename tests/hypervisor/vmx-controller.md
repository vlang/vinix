# VMX host controller

`check-vmx.v` owns the host and cross compiler recipes, architecture-adapter
copies, allocator guards, optimized instruction/CF/ZF checks, operand and
clobber checks, entry-object builds and entry-byte comparison. The independent
`vmx_test.c`, production V helpers and `vmx.S` remain unchanged.

The public `symbol_bytes(path, name)` ELF reader remains byte-for-byte Python.
Python also keeps argparse, compiler selection, the temporary-directory owner,
actual locale-sensitive generated-text I/O and buffered public prints. Private
phase transport restores the caller's standard descriptors and raw environment
before each compiler or text-capture call. Saved descriptors and the reply pipe
use descriptors at least three and close on exec; actual invoking Python text
codecs feed narrow `subprocess.check_output(text=True)` leaves. These mechanical
bindings and retained syntax receive zero migration credit.

This stage qualifies host orchestration and its independent fixtures. A passing
controller or mocked command sequence does not establish privileged VMX or
nested VT-x execution, kernel boot or QEMU coverage. Baseline toolchain failures
are recorded against the unchanged original controller rather than treated as
passing assembly validation.
