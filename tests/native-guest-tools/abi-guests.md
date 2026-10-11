# Native ABI guest runners

The `tests/SUITE/run` commands compile and supervise ABI guests in V, using
`guesthost/abi*.v`. The thin shell fronts compile the V command directly.
There is no Python build, controller, package server or wrapper on this path.

The maintained suites are abi-scratch, capability-exec, stack-policy,
syscall-policy, dumpability, shared-streams, posix-timer, socket-io,
procfs-allocs, network-options, terminal-jobs, securelevel, execute-only,
procfs-mount and clock-control. Clock-control remains ARM-only.

```sh
tests/capability-exec/run --kernel-dir /path/to/arm/kernel \
  --state-dir /tmp/new-capability-arm
tests/capability-exec/run --arch amd64 --kernel-dir /path/to/x86/kernel \
  --state-dir /tmp/new-capability-x86
tests/execute-only/run --arch aarch64 --expect-readable \
  --state-dir /tmp/new-execute-build --build-only
```

`--arch` defaults to `aarch64`; `amd64` and `x86_64` select the same x86
target. `--kernel-dir` contains a matching ELF64 `bin/vinix`. Without it,
ARM uses `VINIX_KERNEL_DIR` or `kernel`; x86 uses `VINIX_AMD64_KERNEL` or
`kernel/bin/vinix` (`build-amd64-kernel/bin/vinix` for procfs-mount).
Build the desired kernel separately, in an isolated worktree when needed.
Every boot snapshots that binary into private state before making an ISO.
The native runner always uses this existing binary, including when the legacy
`VINIX_QEMU_RT_NO_BUILD` setting is absent.

State directories must be fresh. Without one the private workspace is removed
on success, failure or interruption. `--build-only` requires `--state-dir`
(or procfs-mount's `--work`) to keep its artifacts. `--timeout` overrides the
original `VINIX_QEMU_TIMEOUT` setting and 300-second default.

The original per-suite strict C flags, V object warning exceptions, ASM
inputs, source controls and rootfs data remain in effect. Socket-io and
procfs-allocs keep `--baseline`; procfs-allocs creates the same 1,400 empty
directory entries. Securelevel and execute-only keep `--source` for an
independent C control. Execute-only keeps `--expect-readable`. Procfs-mount
keeps `--case full|reuse`, `--work` and `--prebuilt-init`, including the
single feature marker required by reuse. Prebuilt inputs must match the
requested ELF architecture.

ARM boots with 2,048 MiB, four CPUs by default, and a private 64 MiB ext2
`/root`, using the original filesystem formatting flags. x86 keeps 1,024
MiB, two CPUs and its e1000 packet capture; terminal-jobs requires four CPUs
on both architectures. Securelevel's x86 block fixture gets a private writable
disk. ARM retains `USE_TCG`, `VINIX_QEMU_CPU`, `VINIX_QEMU_SMP`,
`VINIX_QEMU_EXTRA`, `VINIX_QEMU_NETWORK`, firmware and QEMU executable
overrides. x86 retains `VINIX_QEMU_ACCEL`, `VINIX_QEMU_X86_64` and
`VINIX_OVMF_CODE_AMD64`. Both retain `VINIX_CMDLINE`; the private ARM ISO
also requests the ext2 home mount. `VINIX_VM_RUNNER_ROOT` selects prepared
ISO support/cache files, and procfs-mount retains `VINIX_LIMINE_CACHE`.
These paths launch QEMU directly from a disposable ISO.

Every feature and final pass marker must occur exactly once. ARM requests
Ctrl-A x as soon as pass/failure appears, allows ten seconds for QEMU to exit,
and rejects a forced stop or nonzero exit. x86 captures two more seconds after
the first pass/failure and retains its original marker-based exit verdict.
Native cleanup owns and reaps the PTY process, probes before signalling,
restores SIGINT/SIGPIPE handlers and keeps the exact captured serial bytes.
Cleanup output cannot convert a timeout into a pass.

`inputs.json` records source hashes, the linked ELF, native command, controller
executable and marker-policy hashes, selected immutable kernel, ISO, command-line inputs
and guest return code. ARM also records its initial ext2 image hash.

`check-abi-builds.v` qualifies both SDKs and all baseline/readable/reuse variants.
It continues after compiler failures and returns nonzero if any profile fails.
`test-abi-runner.v` exercises real PTYs, marker counts, differing architecture
exit rules, late failures, deadlines, large transcripts, SIGINT and repeated
FD/PID cleanup. `check-abi-guests.v` boots those retained profiles through the
same native image and verdict path as the public commands.

## Qualification and limits

Fresh ARM, Rosetta x86 and ARM ASan/UBSan host profiles pass controller builds,
strict CLI checks, existing-state preservation, fifteen failed-compiler owner
retirements each, and fifteen cold public fronts. Real PTY tests pass on all
three profiles, including raw invalid UTF-8/NUL bytes and one hundred FD/PID
retirements each. Thirty-seven SDK profiles are attempted per host: 29 build
successfully and eight fail strictly in the existing generated fixtures.
Shared-streams, socket-io (including baseline) and terminal-jobs call undeclared
`memdup` in generated C on both architectures. The original compiler recipes
reproduce those errors; warning policy and fixture sources were unchanged.
All twelve original C fixture recipes produce byte-identical ELFs.

Actual prepared ARM guests pass capability-exec, stack-policy, syscall-policy,
dumpability, posix-timer, network-options, securelevel, execute-only (including
PAN-disabled readable fallback), procfs-mount reuse and clock-control. The
original C securelevel and full procfs-mount controls also pass. Securelevel's
ext2 volume passes read-only `e2fsck` and contains its fsynced byte `x`.
The existing ARM stat/poll fixture exceeds its 8 KiB retention bound, and
procfs-allocs fails opening the allocation-tracking proc files on this prepared
kernel. Both are unchanged C fixtures and keep failing verdicts.

Several ABI suites fail on the prepared x86 kernel: capability-exec,
stack-policy, syscall-policy, securelevel and procfs-mount fail; abi-scratch
times out. Securelevel and procfs-mount's independent C controls reproduce the
same failures with the exact kernel SHA256
`38fb88ad76e81bb26f9d84267678cf98cd0ccc0aae10573b9b83ddd5ca0b3f0a`.
No new production kernel build, physical-hardware qualification or complete
allocation-tracked kernel matrix is claimed by this controller translation.
