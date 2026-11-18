# Free unreturned G13 queue records after successful unwind

A failed queue constructor now frees its host queue record after backing
cleanup succeeds. The record has not been returned or installed in the manager,
so it has no remaining owner. The existing failure branch still quarantines and
registers a record when cleanup refuses; successful construction still transfers
ownership to the manager/file. Cleanup and the new free run under the manager
lock, before its outer unlock defer. Independent review found no lifetime,
ownership or locking blocker.

The extracted production constructor retained 10,000 blocks / 1,600,000 host
bytes per 10,000 first-allocation failures before the fix. It now retains zero
blocks and bytes in each of three 10,000-failure batches. Both comparisons use
`MallocNanoZone=0`. A separate direct malloc/free control reproduces the default
nano allocator's 102-block / 16,320-byte statistics step despite explicitly
freeing every pointer; disabling nano removes that step in the control as well.
All diagnostics are retained. The fixture uses a reduced queue type and modeled
backing services; its byte counts are not native kernel object sizes or slab rates.

Offline validation passed:

- ASan/UBSan with `-gc none -manualfree` and fake-stack detection passes 3,640
  constructor cases across seven channel masks, four priorities and thirteen
  failure/success/refusal modes. Safely unwound unreturned records are poisoned;
  returned and quarantined records remain live for their owners. Five compiled
  baseline/mutated cases reject missing, quarantined-owner, returned-owner and
  double frees. Six generated-C mutations are rejected.
- All 73 focused test files pass. Existing sanitized G13 failure handling,
  3,672 context-retirement cases and 1,008 deferred-FIFO cases pass, including
  their complete-wire and invalid-input checks.
- Isolated ARM/x86 builds pass. Native C contains twelve lowered copies of
  the single new cleanup-success free arm; removing exactly those arms restores
  the whole baseline constructor. Returning error branches only unlock and
  return their already-built empty result afterward. Successful return sets
  completion before its defer, preventing free. Thirty-five heap, backing,
  context, quarantine and ownership bodies and three owning layouts match
  baseline. The unchanged strict x86 checker confirms whole-C equality with
  its existing discard-variable path-hash normalization.
- Allocation sites/source counts remain ARM 379 / 835 and x86 289 / 813.
  Per-file/per-kind counts and existing allowance-check failures are unchanged.
  No allocation allowance or historical evidence checker was edited.

This also corrects the deferred-context comparison: Asahi's `queue/mod.rs`
passes `buffer.any_ref()` into `GpuContext::new`; `fw/workqueue.rs` stores that
reference in `_buffer`. The retained `BufferInner` owns both per-VM allocators,
and both allocator policies hold an `mmu::Vm`. Thus its context-list entries
retain TVB backing and VM owners transitively. Vinix still retains additional
queue graph state through acknowledgement and UAT cleanup. The source-reference
gate checks this ownership chain as well as owned partial Asahi construction.

The whole-driver audit remains **not_equivalent** against packaged Asahi
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. Returned queue-record reclamation,
allocator backing/accounting, modern UAPI/Mesa integration, remaining stage
backing/event destruction, firmware lifecycle and native execution/performance
remain open or unqualified. Full parity is not certified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-queue-unwind-20261117/`.
Baseline `1c99a4d578d14117d9df979bcc5237555dcd440f` plus only a `gpu/g13.v`
overlay was built in a private worktree. Pinned Omarchy/package revisions remain
`3b36b9e19ea00a6c21492098308a7f44a8091564` /
`6aa71681da0fa53944f230e2d6b807bf852f2b0b`. The full bundle retains source,
C, binaries, inventories, baseline, negatives, source audits and lifetime review.
Malloc diagnostics, an initial source-guard variable error and a versioned Rust
constructor-name correction remain with the final passing runs. The original
inventory checker verifies both the complete bundle and full archive restoration.
`completion.txt` binds committed feature sources/reports to those bytes.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `57a0f3df96cd41b5472628a6ad959c02149f6f957303daea77087997683f408c` |
| `bundle.tar.gz` | `ec24d73c4377ae0bffa733c57553c62e4591d70633e9b45655fe64544514574d` |
| `bundle/vinix-aarch64` | `d20f2a1f457c50631632fbbcfd7a107e0f0b73335165a595f263a8653ae15c6f` |
| `bundle/vinix-x86_64` | `46db071c95a59cf147fa92927d4fbb811fdb9754cb7bffe9b1310c6a9aa6f105` |
| `bundle/blob-aarch64.c` | `865eb298121fefddd91ab4c47cb38e9b32fc2b0039c650f8270cc544a3730e28` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.

## Notifier list head

G13 queue construction now initializes the notifier list's `next` pointer to
the GPU address of the list head. The head starts at offset zero in the shared
record on both firmware layouts. The previous pointer landed eight bytes into
the head, at the `next` field itself.
[Pinned Asahi constructor](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L488-L494)
[Pinned notifier layout](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/event.rs#L17-L29)

The constructor sanitizer fixture reproduced the old pointer as `0x8008`
instead of `0x8000`. The patched fixture checked the head pointer on each
successful construction in the 3,640-case matrix and passed all 64 shutdown
handoff cases. The layout test pins the head and `next` offsets independently.
Both kernel builds, 79 V source-contract test files and the pinned reference
checks passed. The allocation scan matched the baseline with 177 existing
findings. M1 hardware validation remains open.

The evidence archive covers `b25b634a90829d3100dc05fb5a267366a418dc14` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-notifier-head-20261119.s50seM/bundle.tar.gz`
with SHA-256 `7fec3782c4cc2bc2df04a806b769910ea2132020e36d5c0b50aadc506e275e9e`.
