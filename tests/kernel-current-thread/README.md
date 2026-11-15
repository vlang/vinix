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
