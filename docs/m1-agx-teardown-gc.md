# Normal G13 teardown preserves deferred firmware ranges

Render-buffer, queue, render-job and compute-job teardown no longer run full
GC on the private and GPU-read-only heaps. Those six calls could collect
unrelated pending firmware ranges after a failed or skipped cache barrier.
Teardown now marks the records released and leaves their reuse to acknowledged
prefix collection, matching Asahi's private `HeapAllocation` drop policy.

Shared immediate-release behavior, UAT/cache gates, physical backing release,
events, scene slots, completion callbacks and the release/collector methods are
unchanged. Initialization and stopped-firmware channel/event teardown retain
their explicit drains. Independent review found no lifetime or locking blocker:
retained records contain allocation metadata, with no pointer to destroyed jobs
or queues. No allocation or owning field is added.

Offline validation passed:

- The actual baseline and six individually reintroduced GC calls fail the
  pending-owner assertion: seven compiled counterexamples. Six generated-C
  mutations reject premature GC, changed backing release and missing stopped
  state. All 70 focused test files pass.
- ASan/UBSan with `-gc none -manualfree` and fake-stack detection passes 512
  cases using production teardown, scene/slot release, backing dispatch, heaps,
  channel and cache-barrier code. Both ABIs, four teardown kinds, published and
  unpublished cleanup, refusal/retry, idempotence, shared immediate retirement,
  below/above-threshold garbage, failed pre-teardown barriers, delayed acknowledgements,
  failed sends, timeout, device/fault transitions and full/corrupt rings are
  covered. Later releases survive captured-prefix collection; live pins remain
  accessible. UAT, driver buffers, events and PMM are instrumented host services.
- Existing sanitized G13 failure handling, 4,320 heap release-policy cases and
  20,480 mixed policy/reuse/FIFO steps pass.
- Isolated ARM/x86 kernel builds pass. ARM C differs in the four functions only
  by the six removed calls. Thirty-seven allocation, backing, UAT, cache,
  completion, stopped-drain and initialization bodies match after resolving
  string IDs and consistently renaming numbered temporaries. The unchanged
  strict x86 checker confirms whole-C equality after its existing path-hash
  normalization.
- Allocation sites/source counts remain ARM 379 / 834 and x86 289 / 813.
  Per-file/per-kind counts and existing allocation-allowance failures remain
  unchanged. No allowance or historical evidence checker was edited.

Pending metadata and VA may remain reserved while the device is idle, until a
later allocator borrow or shutdown. Below-threshold exhaustion or repeated
barrier failure may return allocation failure. This intentional reservation
policy does not establish native slab rates or a bound on idle retention.

The whole-driver source audit remains **not_equivalent** against packaged Asahi
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. Deferred context invalidation,
allocator backing/accounting, modern UAPI/Mesa integration, remaining stage
backing/event destruction, firmware/cache lifecycle, timestamps, fences/timelines,
wire defaults, topology, power/reset and native performance remain different or
unqualified. These fixtures do not certify firmware execution or full parity.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-teardown-gc-20261117/`.
Baseline `61fa0e06565315adccdaeaac86973c822cb0fd44` plus only a `g13.v` overlay
is built in a private worktree. The complete bundle retains source snapshots,
C, binaries, inventories, baseline, negatives, source audit and lifetime review.
Initial missing fixture imports/constants, a counterexample launched before
baseline preparation completed, and a checker mutation-anchor correction are
preserved with their passing final runs. The original inventory checker verifies
both the full bundle and archive restoration. `completion.txt` binds committed
feature sources and reports to those bytes. Raw results remain outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `601c6220bd06a521096fa9876d27102ea7d095728463640ac6fc29f3c903ba5d` |
| `bundle.tar.gz` | `6a39d5865b78311889fcaadfb0541f4167426f9604cbb15eef237adcfe4d6679` |
| `bundle/vinix-aarch64` | `e1bf18eee72ee563611bb1d010f70484ca598df78cbd67221b0ac77b8a451d1e` |
| `bundle/vinix-x86_64` | `332333c61e804dafc28e83b037faea52a8e7c803987e39403460e120ee69defb` |
| `bundle/blob-aarch64.c` | `a03af15d4a62600370bbcd843df833b53548415545f5a8d42b56abc7b0fc7fd4` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
