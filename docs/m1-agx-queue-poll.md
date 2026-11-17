# G13 publication FIFO per queue

The G13 file worker now records unpublished predecessors in the queue they
belong to. The previous 128-entry scan table stopped looking at unseen
queues after it filled, even when their batches were ready. Asahi creates a
DRM scheduler and entity per user queue. The Vinix change removes the extra
cutoff from its shared poller. [Packaged Asahi queue construction](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs)

The sole poller clears the flag on every queue in a detached snapshot, then
sets it whenever an older retained batch has unpublished work. Each node's
existing reference keeps its queue available through the reset and dispatch
passes. Retained nodes still precede concurrent appends on the next poll.
FIFO-blocked batches still reap timestamp mappings when callbacks finish.

The ASan/UBSan pressure probe puts 128 queues behind an unsignaled fence.
Queue 129 dispatches two batches and a second file dispatches its own queue 1.
A later batch on the original queue 1 waits and resumes in order when the
fence signals. Reinstating the old poller leaves all three ready batches
undispatched and fails the intended assertion. The fixture models admissions
beyond hardware stamp capacity to exercise the software cutoff. Native
stamp allocation and ring admission retain their existing limits.

The async, file-close and firmware-failure sanitizer suites pass. Tests
also cover concurrent append, partial publication, shutdown and retirement
of a FIFO-blocked batch's timestamps. The 82 V test files and five selected
protocol gates pass against the pinned Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`.

The timestamp mutation that skips retirement on blocked batches fails at
its expected assertion. The older mutation runner then stops because its
per-command control expects a different assertion from the one reached by
the newer stage tests. The baseline reproduces that mismatch.

AArch64 MP and x86_64 kernels both build. In the linked ARM kernel, the
poller's stack frame shrinks by 1,280 bytes and the flag fits in the previous
queue-record padding. Generated C shows two linear list passes with constant
lookups and no new allocations. The compiler reports the same allocation
site counts as the baseline, including the existing allowance failures.

Validation used isolated Vinix `6e12263c3` with this patch and injected
hardware events. The concurrent event edit, native runs, deployment and
reboots were outside this check. Full Asahi scheduler policy, DRM timeline
capability reporting and the matched Mesa image remain open.

```sh
ASAN_OPTIONS=detect_stack_use_after_return=1 v run tests/agx-async/run.v
```

Complete inputs, executables, logs and the verified archive restoration are
under `/Users/alex/.local/state/vinix/omarchy-m1-queue-poll-20261117/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `5756fea3608cee05caa65f9530571ca19c3247ff62fcc7e87b6e7050ce3e784c` |
| `bundle.tar.gz.inventory.txt` | `d1df844ab88cab22c826571bdb973bdd256d0df61633554ad20d284adf1386d9` |
