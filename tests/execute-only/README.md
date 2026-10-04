# Execute-only user mappings

An explicit native ARM64 `PROT_EXEC` mapping has instruction-fetch permission
without EL0 data access when enhanced PAN is enabled on every active CPU.
Ordinary `PROT_READ | PROT_EXEC` mappings remain readable. Writable mappings
retain the architecture's existing implicit readability and W^X rules.

Enhanced PAN is necessary because the ARM descriptor denying EL0 data access
is privileged-readable. Ordinary PAN alone would allow raw kernel reads of
that descriptor. Vinix enables SCTLR_EL1.EPAN only when the CPU reports
FEAT_PAN3; any active boot CPU without it, or any disabled PAN configuration,
permanently vetoes execute-only mappings before userspace starts. See the
[Fuchsia architecture analysis](https://fuchsia.dev/fuchsia-src/contribute/governance/rfcs/0159_execute_only_memory#xom_and_pan).

When that gate is false, `PROT_EXEC` retains Vinix's readable executable
fallback. AMD64 also retains that fallback: PKU support is not implemented.
Kernel access audit mode deliberately permits and logs raw accesses after a
PAN fault; use the normal strict mode for enforcement. The existing Apple EL2
PAN default remains disabled unless explicitly requested, so that default also
uses readable executable mappings.

On supported ARM systems, the descriptor sets PXN, clears UXN and uses AP=2.
Checked user copies already require AP[1], so neither a syscall argument nor
an output buffer can read or modify execute-only text through the direct map.
The page-table translation applies to demand faults, mprotect, split ranges,
fork and remap. This adds no allocation or retained pointer. CPU hotplug is
not supported; a future hotplug implementation must preserve the all-CPU gate.

Kernel mappings always set UXN, including executable text. This prevents EL0
instruction fetch and lets enhanced PAN permit EL1 reads of kernel text and
literal pools. An independent diagnostic against matching ELFs executed a
kernel text function from EL0 on the old descriptor; the corrected descriptor
caused an instruction permission fault and SIGSEGV.

The guest checks:

- Native instruction execution and data-read protection, checked input/output
  copies, readable transitions and non-executable writable mappings.
- Independent split permissions, fork inheritance, and a child's writable COW
  transition without modifying its parent's executable bytes.
- Remapped instruction bytes and checked-copy permissions.
- A demand-paged private file mapping and subsequent readable transition.
- 3,000 repeated checked-copy attempts with bounded retained slab memory.

Build allocation-tracked kernels in an isolated worktree, then run:

```sh
export VINIX_VM_RUNNER_ROOT=/path/to/main
export VINIX_KERNEL_DIR=/path/to/worktree/kernel
export VINIX_AARCH64_SYSROOT=/path/to/main/build-aarch64-userland/sysroot
export VINIX_QEMU_RT_NO_BUILD=1 VINIX_QEMU_AUDIO=off
USE_TCG=1 python3 tests/execute-only/run.py

# The same CPU with PAN explicitly disabled must keep readable text.
VINIX_CMDLINE=vinix.user_access=off USE_TCG=1 \
  python3 tests/execute-only/run.py --expect-readable

VINIX_VM_RUNNER_ROOT=/path/to/main \
VINIX_AMD64_KERNEL=/path/to/worktree/build-amd64-kernel/bin/vinix \
  python3 tests/execute-only/run.py --arch=amd64
```

Use `--expect-readable` for an ARM CPU lacking enhanced PAN. The runner treats
warnings as errors and requires all feature markers plus the final verdict.

On 2026-10-02, both tracked production builds passed. QEMU's ARM `max` CPU
passed the execute-only guest, including the actual data-read SIGSEGV and COW
mutation, with Slab at 1,488 / 1,488 KiB across repeated denials. The same kernel
with PAN disabled passed the readable-fallback guest at 1,520 / 1,520 KiB.
A Cortex-A76 CPU with ordinary PAN also passed the readable-fallback guest
at 1,552 / 1,552 KiB. AMD64 passed its readable-fallback and protection
regressions at 1,044 / 1,044 KiB. The older integrated ARM kernel fails the
data-read protection assertion; it allowed that read. Logs are saved locally as
`/tmp/vinix-execute-only-{arm,amd64}-guest.log` and
`/tmp/vinix-execute-only-arm-pan-off-guest.log`.

The generated-production-code harness runs with ASan/UBSan:

```sh
python3 tests/execute-only/check-generated.py kernel/obj/blob.c
python3 tests/execute-only/check-generated.py build-amd64-kernel/obj/blob.c
```

Both blobs passed all protection/gate/COW/attribute combinations. ARM also
passed descriptor masks, all PAN feature values, monotonic system veto and
SCTLR preservation, using adapters for register access and the privileged PAN
instruction. These models supplement the real guests. A Cortex-A72 attempt
stopped before the kernel started and the existing timeout cleanup raised
PermissionError; that configuration supplies no kernel validation.

The final tracked ARM kernel also passes all 45 required original core
checks and the physical EXT2 persistence reboot under TCG, CPU `max` and
four CPUs. The earlier ePAN build stalled in the SMP page-table test; its
artifacts were preserved before correcting kernel UXN. The final focused
guest again leaves Slab at 1,488 / 1,488 KiB. Final ELF, generated C, sources,
logs, helpers and hashes are saved under
`/tmp/vinix-execute-only-final-artifacts/`.

SEC7 remains partial. AMD64 PKU, automatic loader/toolchain use and protected
copy registration for otherwise readable ELF/libc text remain separate work.
