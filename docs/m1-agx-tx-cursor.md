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
