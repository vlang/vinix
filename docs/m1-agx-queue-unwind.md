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

## Firmware 13.5 work-queue record

The G13 initializer now inserts the zero word at `0x84` before the queue state
fields and explicitly writes the trailing zero word at `0xb4`. Those writes
initialize all `0xb8` bytes and preserve the GPU context pointer at `0xa4`.
The previous conversion relied on the queue allocator's initial zero fill for
two words. On a prefilled destination it left the pattern `0xa5a5a5a5` in the
record.
[Pinned queue layout](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/workqueue.rs#L130-L158)
[Pinned queue initializer](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs#L706-L735)

The sanitizer regression reproduces the stale word in the old initializer and
checks the versioned state words, context pointer and guard bytes after the
fix. The temporary common record now stays on the stack in both ABI branches.
The host heap comparison measured 25 allocations from this initializer
before the change and zero afterward, a reduction of 4,800 retained bytes.
AArch64 generated C confirms the stack record. The allocation scan dropped
one finding and reproduced the other 176. Both kernel builds and 79 V
source-contract test files passed. M1 hardware validation remains open.

The evidence archive covers `d8eff76d55dc052e21fde44ef56096d5d72d41f5` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-queue-info-20261119.D2Uk6h/bundle.tar.gz`
with SHA-256 `49d3acb63fb5803287beb3c978b21a900ce47616e7ab20e3d1f9afb5b8a4862b`.

## TVB buffer and render-scene records

G13 initializes every byte of the TVB info record and the render-scene record
before publishing either to firmware. The info initializer clears the active
record before filling its pointers and limits. The Ventura scene initializer
writes the eight-byte zero field at `0x24`, immediately before the statistics
pointer at `0x2c`. The queue allocator already clears its backing. The
initializers now produce the same complete records when given prefilled memory.
[Pinned TVB info defaults](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/buffer.rs#L365-L400)
[Pinned render-scene defaults](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/buffer.rs#L658-L679)

The sanitizer regression reproduced stale bytes at the start of the info
record and in the inserted scene field. It checks the complete records on
both firmware layouts, including the bytes outside each write and the
unchanged destination after a short-buffer refusal.

Both kernel builds, 79 source-contract test files and the pinned reference
checks passed. The TVB growth suite passed its ownership and unwind checks.
AArch64 generated C shows no allocation in either initializer. The allocation
scan matched the 176 baseline findings. M1 hardware validation remains open.

The evidence archive covers `9ceb677caa42e29aa70c8d54b20be4601e36ef16` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-tvb-init-20261119.UTXAd6/bundle.tar.gz`
with SHA-256 `c8371324603ef1680a64c3a21d6f7cfcf99420404c8044c5b64f492df5e376eb`.

## Notifier record initialization

G13 now clears the common `0xa8`-byte notifier record before setting the
threshold pointer, generation and `0x50` control word. The eight-byte Ventura
tail is filled with `0xff`, as in pinned Asahi. This gives the record a zero
current count and empty event state even when its backing is prefilled.
[Pinned notifier defaults](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/event.rs#L30-L88)
[Pinned queue constructor](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L496-L512)

The sanitizer regression reproduced a stale current count in the previous
initializer. It checks every byte of both firmware records, verifies guard
bytes and checks that short destinations and a zero threshold write nothing.

Both kernel builds, 79 source-contract test files and the pinned reference
checks passed. The queue-construction and shutdown-handoff tests passed under
ASan/UBSan. Generated AArch64 C shows no allocation in the initializer, and the
allocation scan matched the 176 baseline findings. M1 hardware validation
remains open.

The evidence archive covers `cecb6050d22e8b179b9ecb7b57fda65a9d5b925a` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-notifier-init-20261119.xCqJep/bundle.tar.gz`
with SHA-256 `9b9f191d29c32bdbce5c9bb5abee08d36d25d8ced51cd79126eb105404495db8`.

## Work-queue ring state

G13 now clears the entire `0x70`-byte shared ring state and sets its capacity
to `0x500` entries before filling the queue descriptor that references it.
Previously the constructor wrote the capacity and relied on the allocator
to clear the cursors and padding.
[Pinned ring-state defaults](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/workqueue.rs#L80-L101)
[Pinned ring-state constructor](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs#L645-L702)
[Pinned queue capacity](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L61)

The prefilled-buffer regression reproduced a stale done cursor with the old
capacity-only write. Under ASan and UBSan, it now checks every word of the
record, both guard bytes and the absence of writes to a short buffer. Both
kernel builds, all 79 source-contract test files, 122 pinned reference checks,
and the G13 failure and queue-unwind suites passed. The generated AArch64 C
shows the initializer runs before the queue descriptor is filled and performs
no allocation. The allocation scan matched the 176 baseline findings. M1
hardware validation remains open.

The evidence archive covers `e1442d84ed6ad1abf4600f2c176f8d5f24879de8` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-workqueue-ring-init-20261119.CFoYvj/bundle.tar.gz`
with SHA-256 `f35d80e30a8dbac08ef6bbcdc0ce51fabb031eac0ec668de09aeb6fed456680a`.

## Notifier list and threshold defaults

The G13 constructor now clears the `0x18`-byte notifier list before linking
its `next` pointer to the head, and clears the eight-byte threshold before the
notifier references it. The queue allocator already clears the backing. The
constructor now establishes the same defaults on prefilled buffers.
[Pinned notifier list defaults](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/event.rs#L15-L28)
[Pinned threshold default](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/event.rs#L66-L69)
[Pinned queue constructor](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L488-L512)

The sanitizer fixture uses the production list layout and prefilled backing.
It caught stale list fields on the old constructor and a stale threshold when
only the list was cleared. With both writes it checked the list, threshold
and guard bytes in the 3,640-case constructor matrix. All 64 shutdown handoff
cases also passed. The generated AArch64 constructor differs by two zeroing
writes, with the threshold cleared before the notifier is initialized.

Both kernel builds, the G13 layout and failure suites, 79 source-contract
test files and 122 pinned reference checks passed. The allocation scan
matched the 176 baseline findings. M1 hardware validation remains open.

The evidence archive covers `f80c6ed4f8fa3968e241cc4faacc6043ba315d9e` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-notifier-list-threshold-20261119.Gv8X4B/bundle.tar.gz`
with SHA-256 `fcc62a5777ba07b8c908176e8b9cc3c2ef762780641a5f7290c72c5130689d08`.

## Shared TVB control records

G13 clears the block-control record, counter, statistics record and 64-byte
kernel buffer during render-queue setup. The statistics reset flag starts at
one. The constructor writes these defaults before filling the TVB info record
and growing the initial eight blocks. The allocator already clears backing
pages, so the prefilled fixture verifies the constructor's own writes.
[Pinned TVB control layouts](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/fw/buffer.rs#L17-L45)
[Pinned TVB constructor](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/buffer.rs#L352-L411)
[Pinned array initialization](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/object.rs#L657-L675)

The sanitizer regression caught stale bytes in the old block-control record.
It now checks every byte and a trailing guard for all four buffers across both
firmware ABIs, including with the VM dormant. The TVB growth suite also checks
that allocation and flush failures release the unpublished graph.

Both kernel builds, the G13 layout and failure suites, 79 source-contract
test files and 122 pinned reference checks passed. Generated AArch64 C shows
four bounded clears before the initial growth, with no implicit allocation.
The allocation scan matched the 176 baseline findings. M1 hardware validation
remains open.

The evidence archive covers `5f32129142a2291fe2b1fbd00295954d7901f8be` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-tvb-control-defaults-20261119.YLdca3/bundle.tar.gz`
with SHA-256 `0ed2a812d8ccc8cd0239149c2e7dde5017446fbaacfa480f98235209da659730`.

## GPU-only TVB block publication

G13 grows the tiled vertex buffer through the GPU-only page-table mapping path.
The UAT allocator completes the outer-shareable range TLBI for a resident VM.
A dormant VM gets its ASID invalidation when its root is installed. TVB growth
publishes the page list, block list and counters only after all new blocks are
mapped. This removes a firmware-control round trip per new block in a bound VM.
[Pinned TVB allocation and publication](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/buffer.rs#L485-L538)
[Pinned UAT map completion](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L627-L663)

The sanitizer regression caught the old firmware-control call. The revised
fixture verifies publication for bound and dormant VMs. Injected allocation and
mapping failures preserve the existing tables and counters and release staged
backing. The cached-buffer teardown fixture still exercises the firmware cache
flush retry. The production UAT sanitizer suite checks mapping, rollback,
invalidation, and root publication on the host.

Both kernel builds, the G13 failure suite, 79 source-contract test files,
and 122 pinned reference checks passed. Generated AArch64 C confirms that
the growth path uses the GPU-only allocator and that the resident range
invalidation uses outer-shareable TLBI with completion barriers. The
allocation scan matched the 176 baseline findings. M1 hardware validation
remains open.

The evidence archive covers `fdd8d95c6141b436f41fce0efca6bcf719abaef5` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-tvb-tlbi-20261119.QqqUCK/bundle.tar.gz`
with SHA-256 `e82b256174f79cf7d2b0525b41c61cd193269907ec2002de47dcf31033f2f9d4`.

## GPU-only render and compute scratch mappings

G13 prepares the five GPU-only render buffers and the compute preemption
buffer through the UAT page-table path. This removes five firmware-control
round trips per render job and one per compute job. The retained flushes
cover the private render tail-pointer cache and the kernel buffers.
[Pinned render scene allocations](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/buffer.rs#L562-L602)
[Pinned auxiliary framebuffer allocation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs#L596)
[Pinned compute preemption allocation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/compute.rs#L80-L89)

The sanitizer fixture executes the production preparation tails. It caught
the previous render flushes and exercised all twelve retained flush failure
points. At each failure, preparation stops and leaves the publication flag
set for cleanup. The job lifetime and UAT sanitizer suites passed. The
render-wire fixture was updated to use the job's bound VM slot. All 32,000
wire cases passed with that fixture.

Both kernel builds, 79 source-contract test files and 122 pinned reference
checks passed. Generated AArch64 C confirms the retained flush calls and
their order after the publication flag is set. The allocation scan matched
the 176 baseline findings. M1 hardware validation remains open.

The evidence archive covers `47de0f8d14a42957ae1ceb58eaedb4362c42c744` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-job-scratch-tlbi-20261119.L0KSCW/bundle.tar.gz`
with SHA-256 `0dc9d2f7f80d090f71883ff62e074e7202b671b00e0dd59e39ab858bbeb413d5`.

## Cached TVB list and tail-pointer cache mappings

G13 publishes the cached TVB page list, block list and render tail-pointer
cache through the VM's UAT page-table path. Queue creation in a resident VM
avoids two firmware-control round trips. Render preparation avoids one,
including when the job reuses the previous tail-pointer cache. Cached teardown
still reprotects the mapping and waits for the required cache flush before
unmapping or releasing its backing.
[Pinned per-VM allocator protections](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L586-L613)
[Pinned UAT map completion](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L627-L663)
[Pinned cached teardown](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1454-L1508)

The lifetime sanitizer fixture caught the old TPC and TVB list flushes in
separate baseline runs. It exercises all 17 kernel-flush failure positions for
both resident and dormant queue construction, and all 11 render and compute
kernel-flush failure positions. The TVB, UAT and queue-unwind sanitizer suites
also passed. The generated AArch64 cached user-buffer teardown body matches
the baseline byte for byte.

Both kernel builds, 79 source-contract test files and 122 pinned reference
checks passed. The allocation scan matched the 176 baseline findings. M1
hardware validation remains open.

The evidence archive covers `37d9fd37a4b22963171c559262a6a8bfe5d39578` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-cached-user-tlbi-20261119.SsKjDg/bundle.tar.gz`
with SHA-256 `ea20bbb17feff637cb1038bf2e6b7b742c6fc09f7c4dba1f5e8b932b2e8d7e07`.

## Uncached kernel-buffer publication

G13 uses UAT page-table invalidation to publish uncached shared kernel
buffers. The preparation helper still rejects missing ranges and forwards
cached ranges to slot 64. A render-only queue avoids eleven firmware-control
round trips. Render and compute job preparation avoid two and one respectively.
[Pinned shared queue allocations](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs#L646-L660)
[Pinned UAT map completion](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L627-L663)
[Pinned cached teardown](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1605-L1635)

The lifetime sanitizer fixture runs the production helper with all four G13
kernel protections. It caught the old uncached failure when the firmware
flush was refused. It also checks every retained cached flush failure in
queue and job preparation. The teardown fixture supplies the refreshed
allocator's host allocation stub and passes all 512 cases. Generated AArch64
C shows the cacheability check before FwCtl, and the kernel teardown body
matches the baseline byte for byte.

Both kernel builds, the UAT and queue-unwind sanitizer suites, 79 source-contract
test files and 122 pinned reference checks passed. The allocation scan matched
the 176 baseline findings. M1 hardware validation remains open.

The evidence archive covers `f17aed4ceee7883d9dea26d5fd90b77fcf0b8c65` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-shared-kernel-tlbi-20261119.p92tuH/bundle.tar.gz`
with SHA-256 `b9f325246ac738f3ad8b04ec06045f3411a73d8005d8546319162a31cb5f91b2`.

## Render and compute job preparation

G13 prepares job buffers through UAT page-table invalidation and exposes the
commands when submission publishes the work-ring pointers. This removes six
remaining firmware-control round trips per render job and two per compute job.
Returned jobs keep their mapping cleanup obligations. Later barrier updates
and cached teardown use their existing cache maintenance paths.
[Pinned kernel mapping and TLBI](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L921-L946)
[Pinned work-ring publication](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs#L509-L522)

The sanitizer fixture caught the old render preparation flush on the baseline.
It checks that both production preparation tails complete without a flush and
retain their cleanup flag before submission. The job lifetime, UAT and
32,000-case command-wire suites passed. Generated AArch64 C confirms that job
preparation omits the flush, while the queue preparation, barrier and cached
teardown bodies match the baseline byte for byte.

Both kernel builds, 79 source-contract test files and 122 pinned reference
checks passed. The allocation scan matched the 176 baseline findings. M1
hardware validation remains open.

The evidence archive covers `5d08a5ba813ef445ea45678d02068c22f2fec70c` plus
`source.diff`. The original and restored copies passed verification. The
archive is at `/Users/alex/.local/state/vinix/omarchy-m1-job-prepare-tlbi-20261119.BkmbI9/bundle.tar.gz`
with SHA-256 `d52ae1ff932d4d07a309b4d76cfb097620dca0652034be2e87c6bd152899070d`.
