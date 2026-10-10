# Native VMX checker

`check-vmx` compiles and invokes `check-vmx.v` directly. The `vmxcheck` module
owns the CLI, compiler selection, temporary directory, host/cross recipes,
allocator guards, optimized instruction checks and ELF64 entry-byte reader.
The old Python frontend, phase protocol and Python text-subprocess leaf are
retired. The independent `vmx_test.c`, production V helpers and `vmx.S` are
unchanged.

The command checks all 7,680 host control ABI cases, ARM no-op behavior,
immediate CF/ZF capture, VMWRITE/VMREAD operand order, flags and memory clobbers,
and allocator imports. `--original PRE_PORT_VMX_C` compiles the original C and
compares every `vinix_vmx_enter` instruction byte using the native ELF reader.
Malformed ELF ranges, strides, indexes and symbol addresses return bounded
errors. Ordinary valid ELF files retain the original extraction behavior.

Compiler and fixture commands retain inherited standard descriptors, raw
environment entries and the caller's ARM/x86 preference. Captured nm and
objdump output uses native strict UTF-8 decoding with universal newlines;
diagnostics use native errors rather than Python exception classes and locale
codecs. The generated C reader uses the shared native text policy. Temporary
source/object trees are removed on success and ordinary failures. `TMPDIR`
selects the private temporary parent. The command preserves earlier fixture
and instruction reports if a later phase fails.

The native tests cover malformed ELF files, full-width addresses, Unicode
names, instruction/ownership regressions, compiler search, all 27 standard
descriptor states, repeated capture, decoding-error precedence, command
failures and descriptor retirement. Set `VINIX_VMX_TOOL` and
`VINIX_VMX_PROBE` to binaries built from `check-vmx.v` and `probefixture` to
include real compilation, pre-port entry comparison, changed-entry rejection,
CLI status/streams and scratch cleanup. These host checks do not establish
privileged VMX execution, nested VT-x, a kernel boot or QEMU coverage.

ARM, Rosetta x86 and ARM ASan/UBSan builds pass all four native test files,
including real Clang sanitizer fixtures and pre-port entry-byte comparison.
The cold launcher passes from an unrelated working directory, emits the exact
fixture reports and removes its scratch files after success or a missing
compiler. Logs are `/tmp/vinix-vmx-{arm,x86,asan}-final.log` and
`/tmp/vinix-vmx-cold-final.log`. No Python was run during qualification.
