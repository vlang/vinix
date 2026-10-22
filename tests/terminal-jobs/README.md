# Terminal job control

The guest establishes a PTY session and tests background read/write/terminal
control permissions, blocked and ignored dispositions, TOSTOP, default stops
and foreground restart, Ctrl-C/Ctrl-Z group signals, and group/session
validation including successful exec. It checks one controlling terminal
per session and `/dev/tty` across detach and replacement. Repeated rejected
reads and controlling-terminal opens measure the guest slab before and after
1,000 calls. The SA_RESTART fixture delays input until after its handler
returns, requiring the restarted call to block again without a stale signal wake.
Stopped groups are resumed when setpgid or setsid orphans them. Session-leader
exit sends HUP/CONT to the foreground group, clears remaining members' terminal
identities and allows another session to claim the same terminal. Scalar group
and session holds cover terminal state and delayed signal delivery, preventing
PID reuse from redirecting them.

Both architecture guests pass. Controlling-terminal open loops stay flat:
ARM 1,552→1,552 KiB; x86 1,140→1,140 KiB. Before the optional-interface
dispatch fix, the ARM loop retained 16 KiB per 1,000 opens. Generated C now
uses one concrete stack slot with no interface `memdup`. Rejected reads stay
flat on ARM and retain one fixed 4 KiB warmup page on x86. The repository-wide
allocation allowance check still has the previously documented baseline failures.

The follow-up builds exposed V promoting synchronous 512-byte I/O locals to
heap allocations: 1,000 rejected reads retained 544 KiB on ARM and 584 KiB on
x86. Explicit caller-stack buffers remove those allocations. Both architecture
guests now pass the hangup and orphan-mutation cases. Terminal opens remain
flat (ARM 1,424→1,424 KiB; x86 1,004→1,004 KiB); rejected-read measurements
retain bounded measurement overhead (16 KiB ARM and 8 KiB x86), whose procfs
formatter sites have a separate repair workstream.

Dynamic terminal opens now retain their endpoint under the lookup/state lock,
and descriptor creation adopts that reference. A full descriptor table tests
100 failed opens and verifies every slave-open count rolls back. A mknod alias
also forwards the owned reference. Three threads race `/dev/tty` opens against
100 master closes, then use and close each returned descriptor. Allocation
tracking exposed a slave-close callback waking an already freed pair; a closer
hold now keeps the pair alive through wakeup and recursive pathname removal.
Both tracked architecture guests pass all 100 races with zero errors. After
six actual seconds of grace (including interrupted sleeps), slab usage falls
from 2,336 to 2,320 KiB on ARM and 1,188 to 1,164 KiB on x86. These builds
include the separate procfs, stat/poll scratch, and unpublished-thread fixes.
The generic VFS borrowed-node lifetime and retained mknod backing pointer
remain separate work; this result covers the controlling-terminal handoff.

Run `tests/terminal-jobs/run`, or add `--arch=amd64`. Isolated
kernels and cached VM tooling use the same environment variables as
`tests/stack-policy/run`. The test requires four virtual CPUs.

The independent fixture is maintained in `guestfixture/core.v`; its native
header contains libc declarations and layout assertions. Generated C is a
build artifact. The port preserves the original 89 check sites, signal and
pthread callback identities, volatile shared words, atomic memory orders,
six elapsed seconds of retirement grace, loop counts and memory bounds.
The runner keeps the original 300-second default deadline and four-CPU guests.
The original 568-line C control remains available in Git revision `13c5160a`.
Its separate readiness fix in `66513801` waits for both orphan-signal handlers
within the original bounded poll before the unchanged assertions. The V
fixture includes the same fix; the C and V controls pass on both architectures.

The [native V controller](../native-guest-tools/abi-guests.md) accepts
`--state-dir FRESH-DIR` to retain artifacts and `--build-only` to qualify the
fixture separately. Every run snapshots an already-built matching kernel.

An idle PTY slave also has a bounded epoll regression. Releasing an epoll
snapshot's temporary resource pin must not wake the same slave again: that
self-wake previously kept even a finite `epoll_wait` in the kernel indefinitely
and stalled actual Neovim terminal input. The fixture checks a timed idle wait,
input readiness and exact consumption, a second timed wait, master hangup, and
a blocked master waking when another process closes the last slave. An alarm
bounds the regression child, and its parent requires successful reaping. Actual
descriptor closes retain their wake; pathname removal and closer holds are
unchanged. Independent lifetime review checked those cases before commit.

The [2026-10-23 receipts](results/2026-10-23/epoll/receipt.json) retain serial
logs, results and source/toolchain/generated-C/ELF hashes. The same final ARM
fixture refuses the old kernel after its five-second alarm. Patched kernels pass
the complete suite on ARM and x86, including 100 concurrent terminal-close
races. One earlier ARM run passed all epoll cases but exceeded the existing
terminal-open slab allowance (2,832→2,848 KiB, allowance 8 KiB); the unchanged
repeat was flat at 2,800 KiB. Both runs are retained, and the allowance is
unchanged. This timing-dependent measurement remains a separate limitation;
these runs do not establish that all kernel allocation paths are leak-free.

For an already compiled static guest and kernel, build `check-prebuilt.v` with
the `tests/hardware-platform` module path and invoke
`check-prebuilt GUEST aarch64|x86_64 FRESH-OUT KERNEL`. It retains boot media,
serial output and `result.json`, refusing any failure marker. Set `VINIX_ROOT`
to the checkout containing the QEMU/firmware tools when building the controller
in a sparse worktree. x86 uses the raw-initramfs ISO helper for older kernels.
These receipts use the clean V `826e96f` kernel compiler rebuilt with fallback
disabled, LLVM clang and LLD; the fixture, controller and x86 heap-sampler
generator use pinned V `fd996fc`. Both architecture kernels force a fresh
object build. The generated x86 heap sampler is preserved with make's
`-o obj/heap_benchmark.c` because its host generator requires the newer V.
This records the actual build inputs and makes no bit-reproducibility claim.
