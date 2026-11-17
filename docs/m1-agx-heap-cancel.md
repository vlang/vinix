# Failed GPU mapping cancels only its unpublished reservation

Kernel-buffer mapping failure now cancels the new VA reservation directly.
Previously it marked that record released and ran full heap GC, also collecting
unrelated pending firmware ranges. Cancellation leaves their FIFO ranks, counts,
bytes and addresses intact while immediately reclaiming the failed reservation.
Generic and G13 callers share this buffer helper.

The cancellation API requires a live reservation that has never been published
to a firmware consumer. Its sole production caller satisfies that condition:
the buffer has not returned, and `pgtable.map()` rolls back partial mappings and
completes deferred TLB invalidation before reporting failure. Cancellation then
unlinks and frees metadata under the heap lock; physical backing is freed next.
Existing release and explicit-GC methods are unchanged. Independent lifetime
review found no blocker. The new method adds no allocation or owning field.

Packaged Asahi `bed544bdf93a496ebf70ba180923bab12b6e01cf` similarly keeps its
new range node local through fallible backing/CPU-map work and only then wraps
it in `HeapAllocation`. Failure does not collect unrelated garbage. Vinix's
different backing policy remains outside this comparison.

Offline validation passed:

- The original production rollback fails the pending-owner assertion. Eight
  compiled negatives reject full-GC rollback, omitted cancellation, cancellation
  of pending records, missing free/unlink/frontier restoration, early physical
  free and corrupted pending counts. ASan catches the missing unlink.
- ASan/UBSan with kernel GC settings passes 9,216 independent history/FIFO model
  cases covering heap policies, unaligned starts, padding, release/cancel masks,
  both cancellation orders, ignored pending records, live pointers and reuse.
- Another 128 cases execute the actual allocator, buffer helper and page-table
  code. An observer proves two leaves exist before injected allocation failure
  at the third. Rollback and TLB invalidation precede cancellation and PMM free;
  pending metadata and a live mapping survive, and the canceled hole is reused.
  Physical memory uses a host fixture.
- Three unsanitized host measurements of 10,000 cancellations retain zero
  blocks and bytes while preserving an unrelated pending record and live pin.
  All 69 focused test files, sanitized G13 failure handling, 4,320 heap policy
  cases and 20,480 mixed policy/reuse/FIFO steps pass.
- Both isolated native builds pass. ARM C verifies one allocation-free
  unlink/free with no iterator or record access afterward, the deferred unlock,
  and exactly the failed-map caller substitution. Twenty-four existing heap,
  backing, barrier and page-table bodies match after resolving strings and
  consistently renaming numbered temporaries. Five checker mutations fail.
  The shared V compiler advanced during validation; a fresh baseline generated
  with the current compiler passes the unchanged strict x86 whole-C checker.
- Allocation sites/source counts remain ARM 379 / 834 and x86 289 / 813.
  Per-file/per-kind counts and existing allowance failures are unchanged.
  No allowance or historical evidence checker was changed.

The source audit still reports **not_equivalent**. Eager job/queue/render-buffer
teardown GC remains a separate collection-policy gap. This does not qualify
native slab rates, backing/accounting, modern UAPI/Mesa integration, remaining
stage backing/event destruction, firmware/cache lifecycle, timestamps,
fences/timelines, wire defaults, topology, power/reset or full driver parity.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-heap-cancel-20261117/`.
Baseline `841a47e3d9ae06737212449e8bfecf5b1788156b` plus allocator/manager
overlays is built in an isolated worktree. A separate clean baseline supplies
current-compiler x86 C. The complete bundle retains source snapshots, binaries,
C, inventories, original/final audits, counterexamples, retention runs and
review. Initial fixture-name and checker-scope failures and compiler-drift
diagnostics are preserved with passing corrected runs. The historical inventory
checker verifies the full bundle and archive restoration; `completion.txt`
binds exact committed feature sources and reports. Raw results remain outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `0b504fcc6d3d0ba2775123a73cfef3664e792d785481ec54121015e16b7a3539` |
| `bundle.tar.gz` | `de6a0a091be50f86a789cc0cdf21e19bd5af268195031b4b34267c5991aa0553` |
| `bundle/vinix-aarch64` | `e522fcd06be5b32ecd9e94e278cf466fdfa28f276924d75a4597cf31f9f16221` |
| `bundle/vinix-x86_64` | `95d1e77d1ff5b636a12ad3d23718ab3a5340bc0587bfeaf45043060013b75781` |
| `bundle/blob-aarch64.c` | `0227d87fb556586518f0c93afadc9fb4585fee0077927481702bf8c253018d0f` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
