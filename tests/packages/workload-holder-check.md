# Kernel lease attachment in the private launch holder

`launchhold.Command.kernel_lease` requires the Vinix workload lease API in the
single-threaded private holder, before its client forks. The shared caller is
not enrolled. A failed attachment reports setup stage 9, is reaped by the
caller, and never starts the client. There is no fallback in this mode.

The opt-in x86 Windows dispatcher selects it with both `wine_owned_manager`
and `wine_kernel_lease`. Non-Windows/default dispatch and ordinary userspace
holder mode keep their existing behavior. The source descriptor remains
borrowed and close-on-exec. Kernel membership preserves the generation lock
after holder death even though client descriptors are closed before exec.
Holder death returns 137; normal completion returns the saved initial status.

Build `workload-holder-check.v` with the repository and
`tests/hardware-platform` on V's module path, using manual memory management:

```text
CHECK FRESH_OUTPUT ARCH KERNEL SYSROOT GCC_INSTALL CLANG V positive
CHECK FRESH_OUTPUT ARCH ORIGINAL_KERNEL SYSROOT GCC_INSTALL CLANG V baseline
```

The ordinary UID1000 caller invokes the actual `launchhold.run`. Its client
double-forks a session leader which execs and verifies membership. The fixture
kills the holder, waits for the caller's exact status 137, verifies the survivor
is alive and the lease is busy, then requires survivor status 37 and final lock
release. Caller and observer depth remain zero. The unlocked-source control
requires stage-9 refusal before exec. The baseline control supplies a valid
shared lease on a kernel without the API and requires the same refusal.

The repeated-launch check warms 32 complete holder/client cycles and measures
another 32, using precomputed observer paths, fixed slab buffers and matching
observer reads before each 13-second reclamation wait. Every positive live
class, large-page or written-after-free delta fails. The controller preserves
admitted source copies and raw outcomes and writes a final verdict only after
selected/captured input hashes are verified. `tracked` adds allocation-site
collection. These selected-input checks do not inventory the complete compiler
tree, C headers or sysroot.

`generation-launch-check.v` also accepts `kernel` alongside `held` and `unheld`.
Kernel mode compiles the actual package dispatcher with both flags, checks
client depth one and caller depth zero, and exercises both ordinary and low
lease descriptors. Raw guest output is in `guest-outcome.json`; `result.json`
is the final expectation verdict after input/artifact verification.

External checkpoint: `/Users/alex/.cache/vwlaunchkernel-20261115-01`. Both
`aarch64-stable` and `x86_64-stable` pass with every measured delta exactly zero.
Both `*-baseline-final` controls pass. The first x86 attempt retains its failed
three-object slab verdict; its observer allocated a path per cycle. Removing
that observer allocation did not change the holder implementation or relax the
checker. Its original admitted source and result remain preserved.

The original `lease-holder-check.v standard` suites pass on both architectures:
initial 37/126/127/signal statuses, caller death, signal cancellation, 64-child
churn, independent holders and unrelated-child wait ownership. Package dispatch
passes `kernel` and existing `held`; `unheld` refuses at the expected readiness
gate. The host unsupported-platform unit test also passes. Generated C confirms
that attachment is a direct `prctl` before `_Fork`, without a new V allocation
on that path.

This is native primitive/dispatch qualification. Signed Wine holder-death
execution and collection, default activation, owned ARM/GUI and complete
hermetic build admission remain open. Kernels are unchanged from the preceding
[kernel primitive qualification](workload-lease-check.md); this change does not
claim to clear its existing allocation-allowlist failures.
