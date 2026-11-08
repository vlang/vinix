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

## ELF32 handoff

The subsequent CD-to-loader-to-ELF probe also passes. It verifies initialized
data, zeroed/writable BSS, an aligned claimed stack, boot-info fields, FDT
magic and exclusion of kernel/stack pages from the available-memory map.
The loader checks each claimed page through the firmware MMU `translate`
method before transferring control. Host ELF tests cover every truncated
prefix, malformed headers, integer/bounds/alignment errors, unsupported
dynamic loaders, nonexecutable entries and overlapping segments. Both the
ELF and FDT host test files pass.

Artifact bundle: `/tmp/vinix-ppc-handoff-verified`.
Base revision: `86ca85518e2161512ab64a61ab5623670bf60ccb`; exact inputs are
preserved in the bundle's source snapshot and manifest. `SHA256SUMS` digest:
`79830df8a4334c22292869630d5062ad998a8dbe818eb3e575cc4d9ee5f69d0f`.
The loaded ELF is a test fixture; this is not a full-kernel boot.

## Initial kernel takeover

`test-kernel` passes its native SCC console, system-call exception return,
and repeated decrementer interrupt checks. The kernel stops using firmware
and does not return to its prompt. Physical-frame ownership and hash-table
policy host tests also pass, including exhaustion and invalid free cases.

Bundle: `/tmp/vinix-ppc-kernel-stage`, base revision `9992871cd` plus the
exact source snapshot in the bundle. `SHA256SUMS` digest:
`66a3272b5d147821668db970d7050f000660dd41019572749bdfcf8459a943fa`.
This stage has no userspace or interactive shell yet.

## Protected userspace

The subsequent kernel check enters problem state with instruction/data
relocation enabled, completes a getpid-style syscall, and recovers only at
the expected PCs from four deliberate faults: kernel-memory read,
privileged `mfmsr`, text write, and execution on a non-executable stack.
It then returns to supervisor mode. QEMU passes all checks using the
G4-compatible 64-index TLB invalidation sequence.

Bundle: `/tmp/vinix-ppc-mmu-verified`, base revision `d60df15c9` plus the
preserved source snapshot. `SHA256SUMS` digest:
`4f196992a9599bf97d453655b98bbf81de30b7c450a6f1890a0cf124b2037a12`.
This is still a protection fixture; it is not an interactive shell.

## Interactive userspace shell

`test-shell` passes from ISO boot through kernel takeover to a separately
loaded `/bin/init` ELF32 process. It exercises `help`, root and nested `ls`,
`cat`, `pwd`, `ps`, `uname`, `mem`, `echo`, backspace, missing files, invalid
commands and exit. Thirty-two repeated open/read/close cycles preserve the
free-page count. In-guest syscall checks reject kernel pointers, writes to
text, a buffer crossing into unmapped memory and unknown/test-only syscalls;
they also exercise descriptor exhaustion/reuse and a valid page-spanning
file read. USTAR corruption/truncation, capacity, duplicate-name and
unsupported-entry host tests pass. The diagnostic media handoff still passes.

Shell bundle: `/tmp/vinix-ppc-shell-final`, base revision `73f5b1470` plus
the exact source snapshot and `sources.sha256`. `SHA256SUMS` digest:
`e82365c6eab3e4496b282ccf4915cc46046dbf63a57d70bcc9f62e88c5b2bec0`.
Media regression bundle: `/tmp/vinix-ppc-initramfs-media`, base revision
`209da615e` plus its source snapshot. `SHA256SUMS` digest:
`6e02cedcf0a4b1d29f359adf405fb06ff51f0ea1b9ecf6c408689c4a53f64e91`.

This validates the initial PPC kernel and freestanding V shell under QEMU,
not the shared Vinix kernel, ordinary Linux programs, desktop, or physical
iMac G4. The default runner now selects the shell and terminal serial I/O.
