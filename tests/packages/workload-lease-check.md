# Kernel-held workload leases

The private Vinix `prctl` operations below let a launcher retain an immutable
runtime generation until its last descendant exits, including descendants that
double-fork, call `setsid`, exec, or outlive a launcher killed by `SIGKILL`.
This is a kernel primitive. Package launchers do not yet use it, and it does
not complete roadmap section 14's default activation or runtime catalog gates.

## Contract

- `0x56490003`: attach the read-only regular-file descriptor in argument 2.
  The descriptor must already hold a shared `flock`; other arguments must be
  zero. Attachment requires one live process thread and a non-exiting process.
  Pledge requires both `proc` and `flock`.
- `0x56490004`: return the current chain depth; all arguments must be zero.
  Pledge requires `stdio`. No descriptor or kernel lock token is returned.
- An independent kernel-owned shared flock retains the source handle.
  Unlocking or closing the source descriptor cannot release that lock.
  Attaching an inode already in the chain succeeds without adding a level.
- Up to 32 distinct nested groups are admitted; another returns `E2BIG`.
  There is no userspace detach operation. Each group retains its parent until
  its final reference retires. Allocation is charged to the caller's file
  resource budget, and the charge is released with the group.
- Fork inherits the creator's chain, including `CLONE_PARENT`. Threads share
  their process's membership; exec preserves it. Failed process publication
  releases the inherited reference. Process exit releases membership after
  page-map teardown, before publishing the zombie.

The immutable chain uses one reference per process or nested child group.
Fork increments only the leaf. `threads_lock` protects membership publication
and transfer; the final iterative retirement runs outside that lock. Source
shared-lock validation is repeated under the advisory lock table lock when
the independent owner is inserted.

## Native probe

Build `workload-lease-check.v` with the repository root and
`tests/hardware-platform` on V's module path. Invoke the resulting controller:

```text
CHECK FRESH_OUTPUT ARCH KERNEL SYSROOT GCC_INSTALL CLANG V positive
CHECK FRESH_OUTPUT ARCH ORIGINAL_KERNEL SYSROOT GCC_INSTALL CLANG V baseline
```

Architectures are `aarch64` and `x86_64`. `tracked` runs the positive probe
with allocation-site collection enabled. The controller uses manual memory
management, compiles a static Linux guest, preserves admitted probe/controller
source copies, pins compiler-captured V inputs, and rechecks admitted hashes
before writing its final verdict. Keep the complete external run directory.

The ordinary-user lifecycle test closes and unlocks its source FD, execs a
double-forked session leader, attaches a nested group, and creates a
`CLONE_PARENT` child. Killing and reaping the original holder must leave both
generation locks busy. Reaping the last survivor with exact status 37 must
release both. PID1 must retain depth zero. The depth test admits 32 independent
groups, refuses a 33rd, then checks every lock after exit. Negative cases cover
an unlocked source, an exclusively locked source, and spare query arguments.

After 32 warm processes, a matched cohort of 32 more processes each creates
four groups. Fixed snapshot buffers and matched observer reads precede both
13-second reclamation waits. The controller refuses any positive live slab
class, large-page or written-after-free delta. A baseline kernel must fail at
the unsupported-query gate, rather than at an unrelated boot/build failure.

These tests do not dynamically force failed-clone rollback, race a duplicate
source unlock, test pledge policy, or exhaust the charged resource budget.
They do not qualify a signed Wine workload or launcher integration.
The controller's selected-input checks are not a complete inventory of the
compiler tree, C headers and sysroot. Full hermetic build admission remains
a separate requirement.

## Qualification checkpoint, 2026-11-15

Prototype source starts at `c89fc75e1`; external state is
`/Users/alex/.cache/vwkernellease-20261115-01`.

- Production kernels build on both architectures; ARM also builds with
  allocation tracking enabled.
- `arm-console-positive` and `x86-console-positive` pass with every measured
  slab class, large-page and written-after-free delta exactly zero.
- `x86-console-baseline` passes the unsupported-query negative control.
  Earlier ARM baseline control `arm-baseline-02` also rejects the absent API.
- Earlier unmatched observer measurements remain failed, as do x86 attempts
  that omitted explicit serial-console setup. No earlier outcome is promoted.
- The required allocation checker exits 1 on both baseline and candidate:
  each reports the same 179 excess-warning rows with the selected compiler.
  There are no new excess rows; the existing allowlist is unchanged.
- Independent lifetime review found no concrete defect, including the
  in-kernel sibling/exit barrier around fork publication and teardown.

The ARM `idle,apps,drag` desktop run passes in `perf-desktop.json`, using the
retained October desktop binary and cached base initramfs. This checks the
candidate kernel with those artifacts; it does not validate a newly built
desktop. `perf-retention-stock.json` passes `ops,churn,cache`: all 36 operation
rows have zero retained bytes with no changed slab classes; all four programs
complete 300 measured churn runs with zero retained kilobytes and no positive
slab deltas. Three classes retire objects during `/bin/true`. The cache scenario
completes and reports zero written-after-free events. Both harness runs use
the exact `candidate-arm-01` binary, verified again after execution.

All recorded older probe/controller source hashes have matching recovered
source snapshots in `source-versions/`; `source-version-recovery.txt` records
the mapping. Historical failed verdicts remain failed. This document does not
claim full section 14 acceptance.
