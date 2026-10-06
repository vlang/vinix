# Verified-boot protocol fixture

`runtime.py` builds `bootfixture/core.v` as a standalone freestanding ELF,
then exercises the real pinned Limine loader. It prints the accepted handoff
marker only when Limine supplies exactly one authenticated module. The fixture
is separate from the Vinix kernel and has no CRT or unresolved runtime symbols.

The maintained V source supplies the original 120 request bytes statically in
`.requests`; initialization does not overwrite the bootloader's responses.
Native volatile response/MMIO layouts preserve the original 64-bit reads and
32-bit UART operations. Serial output and halt instructions remain in V inline
assembly, with no allocation or borrowed storage escaping.

See [the boot tooling instructions](../../tools/verified-boot/README.md#verification)
for loader and firmware arguments. `VINIX_AARCH64_SYSROOT` and
`VINIX_AMD64_SYSROOT` select native headers for compiler support; these headers
do not add libc or the kernel to the linked fixture. `CC`, `LD` and `NM` select
Clang and LLVM tools. For an independent control, add
`--original-reference /path/to/frozen/kernel.c` with identical loader, firmware
and scenario budgets.

Original-C/V controls on both architectures preserve all four existing
scenarios: accepted handoff and rejected config, kernel and module tampering.
The default scenarios run with Secure Boot disabled. Firmware trust enrollment
is exercised only when the existing `--secure-boot` option and real signing
tools are supplied.
