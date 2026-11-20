# ARM current-thread lookup

`proc.current_thread()` must load the per-CPU thread slot on the same CPU
whose index it reads. A timer migration between those operations can return
the old CPU's idle slot or another thread. The fix saves the complete DAIF
mask, masks interrupts across both loads, then restores the exact mask.
It introduces no allocation, free or thread lifetime change.

Run from the repository under the retained bounded-command limits:

```
v -new-compiler -no-parallel -nocache -gc none -cc cc run \
  tests/kernel-current-thread/run.v /path/to/current/v /fresh/external/results
```

The runner extracts the actual production accessor and setter. The model
forces migration after reading the CPU index and immediately on interrupt
restoration, testing idle and foreign old-CPU slots across all 16 DAIF mask
combinations (8,192 calls). Four mutations must fail: missing masking,
restoration before the slot load, enabling all interrupts, and missing
restoration. The real privileged assembly is compiled for AArch64 but never
executed as a host/Linux instruction. Generated C must retain both memory
clobbers; GCC-O2 assembly must order save, index, slot load and restore.

`build.v ISOLATED_WORKTREE CURRENT_V` prepares a fresh detached worktree's
kernel with only the two accessor inputs from this checkout and symlinks
the untracked dependencies. It records the committed kernel revision and
override digests before running a serial ARM build. The worktree must already
be checked out, with `kernel` available. Build it under the same limits;
do not relax those limits on failure. Output belongs outside Git.

## 2026-11-15 qualification

Current V 0.5.2 cbfc1be passed the model, all four mutation refusals and the
ARM C/assembly checks. The compiler executable digest is an observed build
identity, not a required compiler version.

The successful bundle is
`/Users/alex/.local/state/vinix/android/maps-thread-check-20261115-r6/results`.
Its sibling guard receipt records exit/child 0/0, empty reason, complete
cleanup, elapsed 8,738 ms, peak sampled RSS 326,270,976 bytes and observed
disk growth 188,416 bytes. It includes the per-function clobber check.
The earlier r5 attempt was stopped by shared disk growth; it is not a pass.
The builder's final C-generation check also passed in
`maps-thread-builder-check-20261115-r2` (exit/child 0/0, cleanup complete).

| Evidence | SHA256 |
| --- | --- |
| r6/results/audit.json | e3dd5a8b82a4ca0e060e34b3066af931b9ac50b98ac7f8b3ed0faceaced52080 |
| maps-thread-check-20261115-r6.guard.json | 4b95fcd8b473fd899dbc1e2428c362298b8a233ba82f59d70455aec795711081 |
| maps-thread-kernel-build-20261115-r3.guard.json | 01dc827dbfebf29e6206a25ffcbf410c5960d7bb6d8a740db705e0e5da0498bd |

The full isolated kernel base is b7fd15879f96b7fbe0c76c861ff413413256abef,
at `maps-current-thread-kernel-20261115-r1/source` under that state directory.
Attempt r1 was stopped by shared disk growth (614,993,920 bytes). Attempts
r2 and r3 were stopped by the original 629,145,600-byte aggregate RSS cap
(sampled peaks 642,383,872 and 636,469,248 bytes). r3 invoked make directly,
without the V runner. Cleanup completed for all three. No complete kernel
ELF or guest validation resulted; the change is not deployed to r112.

The [Maps report](../native-android-ws/maps-cookie-snapshot-20261115.md)
records the fault and paused guest. The regression demonstrates a race
capable of producing the observed null pointer; it does not prove that this
was the only cause of that guest's fault. A full bounded kernel build and
fresh guest validation remain required before claiming the crash resolved.

## Follow-up compiler profiling

The accessor fix remains committed as 4ab3de1c4. Direct current-V generation
of the isolated kernel's 205,043 parsed lines reached the checking boundary
at about 414 MB RSS, then exceeded the retained 600 MiB aggregate cap during
reachability (`markused`), before emitting C. This is earlier than
monomorphization; the initial progress update used the wrong stage name.
Checking all library bodies and retaining unused functions also exceeded
the same cap. These were distinct compiler-strategy probes, with no limit
increase and no kernel image modification.

All evidence below is beneath `/Users/alex/.local/state/vinix/android/`;
each receipt retains the exact command and original limits.

| Guard receipt | Result / sampled peak RSS | SHA256 |
| --- | --- | --- |
| maps-thread-kernel-profile-20261115-r1.guard.json | RSS guard, 697,958,400 bytes | 12fe97e563c83ff0f8d08aae28b5084e9a5b85d1c001ce672d5edab7c933bf20 |
| maps-thread-kernel-all-bodies-20261115-r1.guard.json | RSS guard, 643,547,136 bytes | 60db079f7f3dc3721160effbfcf22622d1795780bc62e5eaa49fd38267b23d48 |
| maps-thread-kernel-retain-20261115-r1.guard.json | RSS guard, 651,657,216 bytes | cc952db535d7e8f8e006e4e422bba0f729f8143864df5e85a97189226a02d102 |

All three guards completed cleanup. A read-only feasibility probe of the
unchanged deployed kernel source also failed current-V checks, including
deprecated `usize` spellings, before generation. Its source and historical
bundle were not modified; no old compiler was selected. The receipt
`maps-deployed-kernel-profile-20261115-r1.guard.json` has exit/child 1/1,
complete cleanup and SHA256
6024489c36df66b6dbde008019979bb4318dfb1fc2fcc7a9c4a8722e85f8ab1c.

The next proposed attempt uses the already isolated, fixed current kernel
and current V with a kernel-only 2 GiB aggregate RSS ceiling, retaining the
300-second deadline, 512 MiB shared growth cap, 1 GiB reserve and 4 MiB
output cap. This larger ceiling has not been applied. SDK and focused-check
limits remain unchanged. The r112 guest remains paused, with RAM preserved
and complete private export unresolved; it has not validated the fix.

## Guest validation, 2026-11-20

The fix was validated on the kernel the Maps guests actually run rather than
on current master. The deployed kernel (SHA256 a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151) came from
`pidfd-wait-kernel-build-2026-10-26-r1/kernel-aarch64-r2`: revision
ecbd3964a plus its retained `source.patch`, built by the retained V b5bcdbb.
That compiler has `/Users/alex/code/v` baked in as its root, so today it
compiles against the current vlib and its C does not build. A copy whose
baked root is rewritten to an equal-length path holding the full b5bcdbb
`vlib` (the retained `compiler/vlib` is a partial snapshot; every file in it
matches b5bcdbb) regenerates the deployed C exactly: after restoring the root
path in three identifiers and one string, its SHA256 is the recorded
d472464b984da437c553e6ec044b43389af46b7b9f565b67a00dca1e76a68077. Apple clang has changed since October, so the linked
image is not byte-identical.

The same toolchain with only 4ab3de1c4's two kernel files changed produced
SHA256 89a657a6bc52cff262230fcf6c690e04fcb22188d4e046c4b62e7fa7aabe9a19 (peak RSS 2.3 GB for `make -j4`, beyond the old
2 GiB guard, so it ran unguarded). Its `syscall_trace_ret` masks DAIF, reads
TPIDR_EL1, loads the slot and restores DAIF. Guests r113, r114 and r117 booted
it, reached GMS readiness and opened Maps through onboarding and Add account
with no kernel fault; r112 faulted on the first Maps launch. This does not
prove the race was the only cause, but the reproduced step now passes.

Work tree, rewriting and normalizing helpers (`tools/reroot.v`,
`tools/vshim.v`) and build logs: `maps-thread-fix-kernel-20261120-r1` under
the state directory.
