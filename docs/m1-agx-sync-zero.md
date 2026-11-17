# Preserve modern timeline input point zero

The modern adapter now keeps the captured input fence when `timeline_value` is
zero. Previously it checked that a fence existed, then installed a null
dependency. An unsignaled generic or foreign-queue input could therefore let GPU
work publish early. This corrects the adapter introduced in
`bf309feea4dc9ef2cde667d02ed83fcc5464216c`.

The packaged reference is Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`.
`dma_fence_chain_find_seqno(..., 0)` returns without changing the pointer; the
Rust wrapper returns that same non-null fence. Asahi captures the object's fence
before invoking the lookup. Vinix now passes its locked snapshot to the existing
pending worker. Replacement, reset and handle reuse cannot redirect the wait.
Same-queue elision and completion-error policy remain unchanged.

The isolated kernel baseline is `bf309feea4dc9ef2cde667d02ed83fcc5464216c`
with only `kernel/gpu/agx/submission/modern.v` overlaid. Concurrent event-manager
edits are excluded. No new allocation, reclamation or lock order is introduced;
independent lifetime review found no blocker.

Passed offline checks:

- The complete ASan/UBSan asynchronous submission suite in kernel GC mode,
  including 160 new scheduler cases for generic/foreign waits, own-queue
  elision, signaled/failed inputs and snapshots surviving replacement/reset/
  handle reuse. Empty, missing and foreign objects still fail.
- A compiled negative using the original committed stager fails the designated
  publication-blocking assertion. Compiler failure does not qualify.
- An oracle extracts the unchanged pinned upstream C lookup function and runs
  4,000 zero-point calls with sanitizers. Nonzero-only helpers abort if invoked.
  Rust wrapper source is retained and inspected, rather than compiled.
- Six warmed batches of 1,000 zero-point staging calls retain zero host malloc
  blocks and bytes, for both pending and completed fences. These are host
  measurements, not native slab rates.
- Isolated AArch64 MP and x86_64 builds. ARM generated C differs only in the
  modern stager after compiler discard-path normalization. The original strict
  x86 checker confirms whole generated-C equality after its existing
  normalization. The existing 18-body modern adapter allocation guard passes.
- Allocation diagnostics match the preceding baseline by every file/kind:
  ARM 377 sites across 839 sources; x86 289 across 813. Existing allowance-check
  failures remain, with no allowance or historical-checker changes.

Full parity remains incomplete. Native timelines still use a noncumulative
point map, zero-point outputs still return EOPNOTSUPP, and eventual syncobj/fence
reclamation remains open. Mesa migration, GEM_MADVISE and backing/scheduler/
firmware acceptance retain the limitations in the
[modern interface report](m1-agx-modern-dispatch.md).
No hardware access, firmware execution, Vinix/QEMU boot or reboot occurred.

Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-sync-zero-20261117/bundle/`.
The preceding complete modern-dispatch archive is checked unchanged before
sealing. This bundle retains baseline/current C, both ELFs, V input inventories,
source snapshots, reference/oracle sources, test programs and executables,
negative results and review. Full restoration and both named archive roots are
checked. A post-commit receipt binds committed feature bytes to the bundle.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `c3e30b3a64512318bedfa2df7cf32205cee03386cbe488b97ab0612ca672a93b` |
| `bundle.tar.gz.inventory.txt` | `a0c5483073986ba9c3f92672a2390cfb13d60b9a1b72d2b8b6b8de280978c659` |
