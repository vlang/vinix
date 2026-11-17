# G13 context invalidation on allocator borrow

Queue retirement now appends the existing retained queue object to a release-
order FIFO and returns without publishing DestroyContext. The next supported
G13 allocator borrow detaches that FIFO, processes its snapshot and then checks
ordinary heap-GC thresholds. This follows Asahi's deferred-context scheduling
and swap-before-drain order. Repeated retirement requests cannot append twice.

The list adds three nonowning pointers and no allocation path: one next link
per queue and head/tail in the manager. Existing manager/file owners retain
the queue, mapped context and VM. Each popped node saves its next link before
clearing it. Unpublished failures requeue for a later borrow; published failures
stay quarantined without replay. Successful contexts leave the list, and normal
cleanup retries proceed through the existing UAT gate. Stopped teardown clears
both roots and every node link before bypassing retirement. Independent review
found no source-level lifetime or locking blocker, and native C confirms the
required original-pointer identity without copying or boxing.

Offline validation passed:

- ASan/UBSan with `-gc none -manualfree` and fake-stack detection passes 3,672
  retirement cases, 24 complete wire comparisons and 69 invalid-input cases.
  Another 1,008 four-context cases cover all 24 release permutations, both
  ABIs, three ring positions and seven acknowledgement/transport-failure modes.
  They check FIFO, deferred publication, detached snapshots, bounded retries,
  retained mappings and no replay after late acknowledgement. Actual stopped
  cleanup is exercised with the former node poisoned before a later drain.
- All 72 focused test files pass (71 together plus the G13 failure unit file).
  Eleven compiled baseline/mutated counterexamples fail their designated
  assertions. Eight generated-C mutations reject FIFO, snapshot, replay, link,
  identity, gate and allocator-entry errors. Existing sanitized G13 failure
  handling, 512 teardown cases, 256 threshold boundaries and 528 heap-GC cases pass.
- Isolated ARM/x86 builds pass. The C checker verifies the three exact new
  pointer-only methods, deferred gate, allocator-entry order, stopped clearing,
  pointer defaults and layouts. Thirty existing ABI, heap, backing, owner and
  acknowledgement bodies match after string-ID resolution and consistent
  temporary renaming. The unchanged strict x86 checker confirms whole-C
  equality with its existing discard-variable path-hash normalization.
- Allocation sites/source counts remain ARM 379 / 835 and x86 289 / 813.
  Per-file/per-kind counts and existing allocation-allowance failures are
  unchanged. No allowance or historical evidence checker was edited.

Vinix retains the whole queue graph and VM through acknowledgement and later
UAT cleanup. Asahi moves its context object into the deferred list; that object
transitively retains TVB backing, per-VM allocators and their VM. This ownership
chain is checked in the [queue-unwind comparison](m1-agx-queue-unwind.md).
Vinix retains extra queue graph state, so idle retention and backing-release
timing still differ. If no later
allocator borrow occurs, queued objects remain reserved until shutdown.
Published requests without an observed acknowledgement remain quarantined even
after late completion. These fixtures use host timer, doorbell, UAT and PMM
services; they establish no native firmware timing, slab rate or performance bound.

The whole-driver audit remains **not_equivalent** against packaged Asahi
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. Modern UAPI/Mesa integration,
allocator backing/accounting, remaining stage backing/event destruction,
firmware/cache lifecycle, timestamps, fences/timelines, wire defaults, topology,
power/reset and native performance remain different or unqualified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-context-defer-20261117/`.
Baseline `5e5798e4aaa30917e928b87b585161b64c8610d2` plus only `gpu/gpu.v`,
`gpu/g13.v` and `gpu/g13_context.v` overlays was built in a private worktree.
Pinned Omarchy/package revisions remain
`3b36b9e19ea00a6c21492098308a7f44a8091564` /
`6aa71681da0fa53944f230e2d6b807bf852f2b0b`. Complete sources, C, binaries,
inventories, baseline, negatives, source audit and review are retained. A copied
historical preparation child terminated with status 137; fresh V preparation
completed. Initial test-runner option/result handling and C-checker indentation
diagnostics are preserved with the final passing results. The original inventory
checker verifies the full bundle and full archive restoration. `completion.txt`
binds committed feature sources/reports to the sealed evidence. Raw results stay
outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `1e1b50167789c2ac44ec7717579a95258472862c1abd0442d6e55f58f7073288` |
| `bundle.tar.gz` | `e64f055bc5e5d32fa3f64ec058b1e1c43cc949e34157ad65caca6e08ff69428a` |
| `bundle/vinix-aarch64` | `9a98bac1a79eb699d807bb8bb82c996e7d48fa94ed7419e476a0c15d581441dd` |
| `bundle/vinix-x86_64` | `3db071cdc595fca7bf480d68ba6bb6a61e3d0493484f2bde043dcf204b4e7263` |
| `bundle/blob-aarch64.c` | `344ebdad2442661f3c14c38865ed158d071aded677c3002cc518970513b3996e` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
