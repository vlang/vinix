# PowerPC bring-up validation

2026-11-08, macOS ARM64 host, V `b7b4dd46ee`, Zig 0.17.0,
QEMU 11.1.2 / OpenBIOS 1.1.

CD firmware boot: **pass**. The ELF executes from an ISO9660 CD through
OpenBIOS on `mac99,via=pmu`, CPU 7450, 512 MiB RAM. Guest checks cover the
PPC32 big-endian firmware ABI, PVR/MSR access, clock progress, successful and
failed CAS, cache publication, memory discovery and a copied 50-node FDT.
The host independently validates the FDT dumped from guest RAM. FDT corruption
unit tests also pass. The ISO's ELF extracted with bsdtar matches the input.

Artifact bundle: `/tmp/vinix-ppc-media-verified` (outside Git).
Base source revision: `6366119cb1d5aa6e634a9e14308625e74499294d` plus the
exact implementation inputs preserved under `sources/` and `sources.sha256`.
`SHA256SUMS` digest:
`e187b562dd53d237417f0ffa3111679d63ba13ffc395db1a8e95e82955232ac7`.

Compiler patch validation: 50 parser tests, 1881 compiler-error cases (6
skipped), 8 comptime-definition cases, 104 inout files (92 successful runs,
11 expected panics, 1 skipped), and 332 checked documentation examples.
Compiler test logs are `/tmp/vinix-v-ppc-errors.log` and
`/tmp/vinix-v-ppc-inout.log`. The raw PPC assembly is also exercised by the
guest tests above.

This does not validate the complete Vinix kernel, userspace, desktop, or
physical iMac hardware. The loader currently returns to firmware.
