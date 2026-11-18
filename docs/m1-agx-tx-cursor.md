# G13 transmit cursor validation

Asahi `bed544bdf93a496ebf70ba180923bab12b6e01cf` keeps the TX write cursor
in host memory. Vinix previously used the shared write index as the next
destination after checking its range. An incorrect index within that range
could redirect a control message or a RunWorkQueue publication.

Vinix now seeds a private cursor from initialized ring state before firmware
can access it. With the TX lock held, enqueue and work-ring reservation check
the shared index against that cursor before writing an entry. Each publisher
updates the cursor and publication count when it advances the shared index.
A mismatch latches a channel fault. The batch publisher validates every pipe
before it writes any inner or outer ring entry.

The direct enqueue and batch regressions failed on
`22e7868e94d23a7e0af766386e6ef2ca96d8589c`. The updated sanitizer suites cover
both control header layouts, compute and paired-render publication, 87 batch
transactions, wrap, full-ring refusal and recovery. FwCtl, context retirement,
heap GC, heap pressure and teardown GC suites passed. All 79 local contract
test files and 122 archived-reference checks passed.

Isolated AArch64 and x86-64 production kernels built successfully. Generated
AArch64 C shows one scalar cursor per TX channel and stack-only publication.
The allocation scan reproduced the same 176 baseline findings with identical
counts by file and warning kind.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-tx-cursor-20261119.HloXB7/`.
The `bundle.tar.gz` SHA-256 is
`2cdf85e11b6ee7b59fdd0497ac645f1de58621430eaf425a75c22aafac56bbc9`.
Native M1 firmware validation remains open.

## Inner workqueue write index

Asahi places each command with a host-owned workqueue write cursor. Vinix
now checks the shared `cpu_wptr` against the next slot after its recorded
`last_command_slot`. Fresh queues initialize the last slot to 1279, so the
first valid write index is zero. The compute, paired-render and batch
publishers all check this before writing any entries. A mismatch moves the
manager to its error state and leaves the ring contents untouched.

The paired-render and batch regressions reproduced misdirected publication
on `27597a4768d6baeda0f421654148159350e88b4e`. The updated sanitizer suites
passed 90 batch transactions and the standalone compute and render cases,
including wrapped prefixes and in-range index corruption. The context
retirement and FwCtl fixtures, 79 local contract test files and 122 archived
reference checks passed. AArch64 and x86-64 production builds passed. The
allocation scan reproduced the same 176 baseline findings by file and kind.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-workqueue-cursor-20261119.NI24ou/`.
The `bundle.tar.gz` SHA-256 is
`b88201965f3dfc453bcf25143444e1023f40cc30788f6a8ac9280ac8937cfddb`.
Native M1 firmware validation remains open.

## Workqueue retirement indices

Before advancing `cpu_freeptr`, Vinix now checks the shared `cpu_wptr` and
`cpu_freeptr` against the host's publication and retirement records. It also
checks that the completed job's slot matches its sequence. The expected slots
use the last published slot and the sequence distance around the ring. The
initial free index is zero. An already-retired sequence skips publication.

An in-range mismatch leaves the shared indices and retired sequence intact.
The reaper enters its existing failure path, retaining backing and waiting
for the other render stage when it is still active. Asahi
`bed544bdf93a496ebf70ba180923bab12b6e01cf` uses event stamps and the last
completed command's recorded slot to publish its free index.

The previous revision `db979ec4a8054d13a5db3328b9211771a123f429` advanced
retirement in the corrupt-write-index regression. ASan/UBSan passed the
updated compute and render retirement tests, including wrap, reverse reaping,
failure callbacks and repaired retries. The job-lifetime, FwCtl and context
retirement suites passed, along with 79 local contract test files, 122
archived-reference checks and both production kernel builds. The allocation
scan reproduced the same 176 baseline findings by file and warning kind.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-retirement-cursor-20261119.Jtk3vq/`.
The `bundle.tar.gz` SHA-256 is
`a528a72944e597cda327214b02588b2e9b4fd9fb4f6e17c4948341dbd4a8ee13`.
Native M1 firmware validation remains open.

## Firmware-visible workqueue capacity

Asahi writes the allocated workqueue size to `rb_size` in the shared ring
descriptor. Vinix initializes the field to 1280 entries and uses the same
capacity for host indexing. Compute, paired-render and batch publishers now
verify the descriptor capacity before writing command addresses or advancing
the outer TX ring. A mismatch puts the manager into its error state and
refuses the publication. A batch checks every participating pipe before
publishing any part of the batch.

The paired-render and batch regressions reproduced acceptance of a mismatched
capacity on `7e17410a07b3a90158fdd72abc0ff6f38a8f3add`. ASan/UBSan passed the
updated standalone publisher tests and all 93 batch transactions. The cases
cover zero, smaller and larger advertised capacities and valid ring wrap.
Both kernel builds, all 79 local contract tests and 122 archived-reference
checks passed. The allocation scan reproduced the same 176 baseline findings
by file and kind.

Evidence and the tested diff are stored at
`/Users/alex/.local/state/vinix/omarchy-m1-workqueue-size-20261119.FQGYmf/`.
The `bundle.tar.gz` SHA-256 is
`b9aa8538d3114de69b56c53bfd7a123507a5866ff064763e16560b800e28a498`.
Native M1 firmware validation remains open.
