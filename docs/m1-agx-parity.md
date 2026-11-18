# M1 AGX parity with Omarchy

Status: **incomplete**. Reference: the Asahi driver in Omarchy's packaged
Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`. The source chain and
original comparison are in [the initial port report](omarchy-m1-gpu-port.md).
Same firmware protocol is the target; identical Linux/Rust source is not a
meaningful requirement for a V kernel with different memory and scheduler APIs.

Base M1 G13 uses AIC mailbox receive and send-empty interrupts during RTKit
negotiation, with bounded FIFO polling as a fallback. The send-empty line also
assists application endpoint starts, InitData and the initial doorbells before
the GPU manager is published.
[RTKit boot receive IRQ](m1-agx-boot-rx-irq.md),
[RTKit boot send-empty IRQ](m1-agx-boot-tx-irq.md) and
[Application startup transmit IRQ](m1-agx-init-tx-irq.md)

The base M1 worker can use the same send-empty line for RTKit system replies.
It checks GPU liveness and the FIFO deadline after reacquiring the manager
lock. [Runtime system reply transmit IRQ](m1-agx-runtime-tx-irq.md)

The native G13 batch publisher releases its ring locks before sending
fragment, vertex and compute doorbells. It can use the send-empty IRQ for
these notifications. [Batch doorbell transmit IRQ](m1-agx-batch-tx-irq.md)

GrowTVBAck and RecoverChannel use the device-control tags for the selected
G13 firmware ABI. GrowTVBAck carries the full halt counter and can use the
send-empty IRQ. [G13 device-control commands](m1-agx-device-control.md)

RecoverChannel also uses the guarded send-empty path. It retains the queue
until firmware consumes the command or the ASC stops, and recognizes
completion after ring wrap. [RecoverChannel transport](m1-agx-recover-channel.md)

G13 FwCtl writes the number of 16 KiB pages at offset `0x10` of the 20-byte
cache-flush message. At 65,536 pages and above it logs the overflow and casts the
count to 16 bits, as the packaged driver does. The handoff keeps the full
byte range. FwCtl transmit and completion still poll while the caller
holds IRQ-masking locks.
[Packaged Asahi flush](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1542-L1559)

ARM64 and x86-64 builds, the G13 layout and failure suites, heap and
file-close regressions, all 82 contract files, and 341 sanitizer
transport and handoff cases passed. Nine compiled negative controls
include restoring the fixed count of one. The native ARM64 C emits
the shift and cast before enqueue. The allocation scan reproduced 178
baseline allowance findings. The source audit remains `not_equivalent`.
The checks ran without hardware or reboots.

Evidence for `1efbe7326292d54c09e74c2b6515657dbd3b094e` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-fwctl-page-count-20261118/`.
The archive and restored copy both passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`dbc5e8bf28bdca22bd2833d5989bc46b5fb44df65e678ed6ac25a7ee4b970954`.

G13 driver-owned user mappings follow Asahi's cache teardown order. The
driver makes a cached mapping uncached, completes the GPU TLBI, and sends
FwCtl only if both the ASC's active slot and its TTBR0 match the VM. A
failed snapshot or flush retains the mapping and backing. Unmap completes
the outer-shareable GPU TLBI before backing release.
[Asahi slot and root check](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1466-L1508)
[Asahi final TLBI](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1676-L1698)

Both kernel builds, all 82 contract files, TLB and TVB sanitizer tests,
512 teardown GC cases, job and context lifetime regressions, and two
compiled negative controls passed. Generated ARM64 C and independent
review confirmed the snapshot, flush and release order. The allocation
scan reproduced 178 baseline findings. Whole-driver parity remains
`not_equivalent`. No hardware tests or reboots ran.

Evidence for `a83f3eaac65ac5f9924133e3774883a953ded696` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-user-teardown-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`1a525722dca606934ce3ae1d75be31c7c0fcaf5c12d0eac78e678f4aada154ba`.

G13 kernel mappings complete teardown with the GPU TLBI in unmap. Cached
mappings first complete the slot-64 FwCtl handshake while their uncached
PTEs are still valid. Failed reprotection or acknowledgement retains
the backing. The lower root invalidates the ASID-0 range and the upper
root invalidates global translations. FwCtl transmit and completion still
poll under IRQ-masking locks.
[Asahi kernel mapping teardown](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1605-L1689)

Both kernel builds, all 82 contract files, 353 UAT sanitizer cases, and
teardown, TLB, context and job regressions passed. Two compiled controls
caught a send after unmap and a missing cached flush. Independent
lifetime review found no blocker. The allocation scan reproduced 178
baseline findings. Whole-driver parity remains `not_equivalent`.
No hardware tests or reboots ran.

Evidence for `65d530fbd3e9f96b20e46a9a8961b97d22a1120b` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-kernel-teardown-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`dc09a675951d0a1e08e71109af4353e11bdbeb396f5d36b5cf0306de6915f567`.

G13 GPU-only GEM bindings use the page-table path for visibility and TLB
invalidation under both ioctl ABIs. A resident unmap completes its ASID
TLBI before releasing the GEM backing. Dormant roots get an ASID
invalidation when installed. The manager lock still serializes mapping
completion with shutdown, and a refused state check retains backing for
retirement. Active jobs continue to gate unbind and overlap replacement.
[Asahi map publication](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L643-L674)
[Asahi GEM unmap](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L770-L803)

Both kernel builds and all 82 contract files passed. Sanitizer checks
covered 1,200 modern VM_BIND cases, 200 file retirement cycles, the
resident and dormant roots, device loss and shutdown races. Three
compiled controls caught a FwCtl send, a bind accepted after stop, and
retirement before ASC shutdown. Independent lifetime review passed.
The allocation scan reproduced 178 baseline findings. Whole-driver parity
remains `not_equivalent`. No hardware tests or reboots ran.

Evidence for `5a9cb5994ac93f5618f63febab87599afec5ce2a` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-gem-tlbi-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`4729d926ead4c19620aabdb33f16f6ed48c874060ec2fc2876a2b3161d226d51`.

Both G13 ABIs now accept a valid range unbind with no overlapping records
while the VM has jobs in flight. The pinned Asahi GPUVM walk returns
success for a range with no matching GPUVAs once its preparation succeeds.
Vinix also accepts legacy UNBIND_ALL when the selected VM has no
mapping for the handle. Live overlaps and retained retirement records
still require idle. [Asahi GPUVM unmap walk](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_gpuvm.c#L2708-L2767)

Both kernel builds and all 82 contract test files passed. Sanitizer
coverage includes 15,000 range checks, 1,600 modern VM_BIND checks,
legacy UNBIND_ALL, submission, and TLB tests. The compiled controls
caught rejection of an empty range, acceptance of a busy overlap,
and rejection of a legacy unbind whose handle mapped only in another VM.
The allocation scan reproduced 178 baseline findings. Whole-driver
parity remains `not_equivalent`. No hardware tests or reboots ran.

Evidence for `737faa979b07b9d68a3ba3b4bec3ac7cef91fc9d` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-empty-unbind-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`26a89a90c8586bfb028304af1c5561a192a13fcd46ae1a6a9fab040f36bfce0e`.

G13 UAT completes child-table zeroing with `DSB SY` before installing the
parent descriptor, as in the pinned Asahi driver. BIND preparation visits
each leaf table once, covering up to 32 MiB of GPU VA per lookup. It
preserves existing leaves and retains any empty tables attached before a
later allocation failure.
[Asahi page-table walk](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/pgtable.rs#L660-L756)

Both kernel builds, 82 contract test files, and the TLB, heap, teardown,
and file-close sanitizer suites passed. The linked ARM64 instructions
show the barrier before both parent stores. Three compiled controls
caught late barriers at both levels and a walk that skipped a table
boundary. The allocation scan reproduced 178 baseline findings.
The full source audit remains `not_equivalent`. No hardware tests
or reboots ran.

Evidence for `c1795a97f51df1ba8f548710fca0a3971e8111e2` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-uat-table-publication-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`c2eea80bbab6a1b4351408cf42af7ed3004c7c9ee27abe6ca6fed75cd8b29dd9`.

G13 UAT follows only table descriptors at L1 and L2 and installs a
child only when the intermediate entry is zero, matching the pinned
Asahi rules. Asahi skips subtrees with other descriptor types. Vinix
skips those entries for unmap and fails mapping preparation, map, and
reprotection when they reach one.
[Asahi intermediate descriptor walk](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/pgtable.rs#L660-L720)

Both kernel builds, 82 contract test files, and the TLB, heap, teardown,
and file-close sanitizer suites passed. Six borrowed TTBR1 cases
preserved the unsupported descriptors, their backing and adjacent
leaves. Three compiled controls caught the previous behavior. Both
type checks appear in linked ARM64 code. The allocation scan reproduced
178 baseline findings. The full source audit remains `not_equivalent`.
No hardware tests or reboots ran.

Evidence for `297f1d4e6dc7a0bc26262338dce48d9206db6e10` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-uat-descriptors-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`f8c87d3cff0a3ed7193d8b93207ed9f853514f0335a2d0db11d641431577a349`.

G13 context-zero mapping checks the full destination for nonzero leaves,
then prepares the intermediate tables before publishing any leaf.
One page-table lock covers all three steps on TTBR0 and TTBR1. A collision
preserves the old mapping without allocating tables. If preparation runs
out of memory, the destination stays empty and the root keeps any tables
already attached. [Asahi fixed-map preparation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/pgtable.rs#L894-L908)

Both kernel builds, 82 contract test files, and the TLB, heap, teardown,
and file-close sanitizer suites passed. The linked ARM64 code confirms
that preflight branches precede leaf writes and that publication
completes under the lock. Three compiled controls caught bypassed
preflight, allocation before collision detection, and early leaf
publication. The allocation scan reproduced 178 baseline findings.
The full source audit remains `not_equivalent`. No hardware tests or
reboots ran.

Evidence for `39ac338bf7dbc9404cea3e3ba62ba4f57e2e6cce` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-fixed-map-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`8fbb2a72537b46e1926ee090b385ad884acce8a8e4c7d59fcf94a399d372fc68`.

G13 per-VM driver buffers now use the fixed-map preflight for both
heaps. The pinned Asahi range allocator calls `map_node`, which checks
for occupied leaves and prepares tables before placing the mapping.
On failure, Vinix cancels the new VA reservation and returns its
backing while preserving earlier deferred reservations.
[Asahi range mapping](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L2459-L2504)

Both kernel builds and 82 contract test files passed. The allocator
sanitizer fixture covered 400 contexts and 4000 successful shared and
private allocations, including 800 retries. The page-table, heap
cancellation, TPC, TVB, and cache teardown regressions passed. Two
compiled controls caught a bypassed preflight and collection of older
reservations. Linked ARM64 code confirms cancellation before physical
free on map failure. The allocation scan reproduced 178 baseline
findings. The full source audit remains `not_equivalent`. No hardware
tests or reboots ran.

Evidence for `fe66f619325c910fcbb80b69199095bc479a1715` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-vm-buffer-preflight-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`37130cff00b98d519bfda130eaa233332f45b3115d30c11ff56c714807d3bf90`.

G13 firmware heaps and the fixed buffer-manager mapping now request
one 16 KiB UAT granule of physical alignment. On Vinix's ARM64 PMM,
that removes the three extra contiguous pages required by the old
four-page alignment request. Scatter-backed allocation remains open.
[Asahi page-table mapping](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/pgtable.rs#L929-L944)

Both kernel builds and 82 contract test files passed. The sanitizer
suite passed 256 pressure cases, two fixed-map refusals and a
default-heap control. It checked 4 KiB and 16 KiB PMM arguments and
backing return on failure. Compiled controls caught the oversized
alignment in each G13 path. Linked ARM64 code confirmed both
alignment calculations. The allocation scan reproduced 178 baseline
findings. The full source audit remains `not_equivalent`. No hardware
tests or reboots ran.

Evidence for `41d57c1995067b7690a0def4d78b0dfded3157c9` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-backing-alignment-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`ec73a69ae1be32f6308d3e947ed67ad46f71f2d19595e562ee1e48fc67ab9fef`.

G13 timestamp BIND returns `ENOSPC` through both ioctl ABIs when
the 64 MiB firmware aperture has no suitable range. This revision
returned `ENOMEM` on any page-table failure and canceled the unpublished VA
reservation without collecting other deferred ranges. Both failures
release the temporary GEM reference and preserve the output handle.
[Asahi range mapping](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L2459-L2504)
[DRM MM reservation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_mm.c#L500-L611)

The sanitizer suite filled all 4,096 16 KiB slots using Vinix's real
allocator with a simulated UAT. A further reservation failed before
mapping, and a released slot accepted a retry. It also checked 100
failed-map rollback cycles and 184,000 timestamp ioctl cases.
Three compiled negative controls failed at their expected assertions.
Both kernel builds, 82 test files and the page-table rollback and
async suites passed. The allocation scan reproduced 178 baseline
findings. The full source audit remains `not_equivalent`. No hardware
tests or reboots ran.

Evidence for `0120edec85fd1176b6908b3264a5467186f6901f` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-timestamp-aperture-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`c44fa0cd5321315df3131a8e9f53ebb06e8e4c9447d007493119a562cc64a6f1`.

G13 timestamp BIND now propagates `EBUSY` through both ioctl ABIs
when a destination leaf is occupied. The vacancy scan runs before
allocating tables or writing leaves, as in the pinned Asahi driver.
Page-table allocation failure returns `ENOMEM`. Either error cancels
the new VA reservation and releases the temporary GEM reference.
[Asahi fixed-map preparation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/pgtable.rs#L893-L906)

The real page-table code preserved occupied leaves on TTBR0 and TTBR1
under host fixtures. The sanitizer suites passed 184,400 timestamp
ioctl checks, the 4,096-slot exhaustion case, and the rollback and
flush checks. Two compiled negative controls failed at the expected
assertions. Both kernel builds and 82 test files passed. The allocation
scan reproduced 178 baseline findings. The full source audit remains
`not_equivalent`. No hardware tests or reboots ran.

Evidence for `c7504b1162d0f3da4ae0066c7348dcf783089491` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-timestamp-map-status-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`90bf451e47b66e04e5b745ca8438639c9e49c369128dfe9fb8ef4c483db596ba`.

G13 timestamp BIND now allocates the lowest free nonzero handle
through both ioctl ABIs. UNBIND frees the name immediately when a
command still holds the mapping. Existing captures retain the base GPU
VA and GEM backing so their release still reaches the original mapping
after the handle has been reused.
[Asahi timestamp BIND](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1217-L1232)
[XArray name allocation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/lib/xarray.c#L2008-L2033)

The sanitizer suites passed 184,600 timestamp ioctl checks, 64
same-handle mapping lifecycles and async timestamp retirement. Two
compiled negative controls caught delayed reuse and release by handle.
Both kernel builds and 82 test files passed. The allocation scan
reproduced 178 baseline findings. The full source audit remains
`not_equivalent`. No hardware tests or reboots ran.

Evidence for `e984cf1f8f700af12236ad652109ca800c5dcada` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-timestamp-names-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`c51d501ef3736fae5571a6698a343361a870cf1dff4296b5a8836ec0728d5b97`.

G13 timestamp BIND now returns `ENOMEM` through both ioctl ABIs
if the handle table cannot grow after mapping the buffer. It releases
the file lock, unmaps the new VA and drops the temporary GEM reference
without publishing a handle. Growth preserves existing records and
their captures. [Asahi timestamp publication](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1217-L1232)

The sanitizer suite passed 400 allocation refusals, 200 checks that
mapping errors precede table allocation and 100 growth and close
cycles. Both compiled negative controls failed at the expected
assertions. Both kernel builds, 82 test files and the lifetime review
passed. The allocation scan reproduced 178 baseline findings. The full
source audit remains `not_equivalent`. No hardware tests or reboots ran.

Evidence for `de8789a62c7bd554590c142b0c10ef72399aa429` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-timestamp-publication-20261118/`.
The archive and restored copy passed full inventory verification.
`bundle.tar.gz` SHA-256 is
`c78c3d32258b49d7191934953859600ad6599921dd6e8f92a560078b5d91c524`.

Both G13 timestamp ioctl ABIs now remove the handle on a valid UNBIND
even if the GPU manager is unavailable. The detached record keeps its
VA and GEM reference for worker or close cleanup. A later bind can reuse
the public handle independently of the old mapping. Cleanup requires
access to the original manager. Permanent teardown and manager
replacement remain open.
[Asahi timestamp UNBIND](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1235-L1274)

The sanitizer suite passed 128 manager-loss and restoration lifecycles
across both ABIs and 184,600 timestamp ioctl checks. The worker retired
the original VA after handle reuse and preserved the replacement.
Both kernel builds, 82 test files and the lifetime review passed.
Two compiled negative controls failed at their expected assertions.
The allocation scan reproduced 178 baseline findings. The full source
audit remains `not_equivalent`. No hardware tests or reboots ran.

Evidence for `8d8f5f6b573f99575ed2b0020917531c84a72a8e` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-timestamp-unbind-20261118/`.
The archive created with sparse-file detection disabled passed full
inventory verification against the retained original.
`bundle.tar.gz` SHA-256 is
`01d8d45549f261eb637ac6ac6c1ead83ae089cd7a07a97d9c985ece3f7a72198`.

Both G13 timestamp ioctl ABIs return `ENODEV` if the manager has
stopped by the time a valid BIND reaches the mapper. The check holds
the shutdown lock and precedes VA reservation and page-table writes.
Linux DRM rejects ioctls on unplugged devices at entry.
[Pinned DRM ioctl admission](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_ioctl.c#L844-L851)

The sanitizer suite passed 100 simulated shutdown lock races and
185,000 timestamp ioctl checks. Existing mappings could still be
retired while stopped. The compiled baseline failed the stopped-map
assertion. Both kernel builds and 82 test files passed. The allocation
scan reproduced 178 baseline findings. Mapping publication after a
successful pre-stop map and cleanup across permanent teardown remain
open. The full source audit remains `not_equivalent`. No hardware tests
or reboots ran.

Evidence for `cef64c6b5c9c0c34caef9d631af50a296eacec9c` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-timestamp-stop-20261118/`.
The archive passed full inventory verification. The native outputs
are stored in `native-builds.tar.gz` and verified against their original
hashes. `bundle.tar.gz` SHA-256 is
`5090cd359d9efa10d72723d088973e51f57f18bc940eaac5df5d2e67a562f926`.

Both G13 timestamp BIND ABIs now hold the shutdown lock while installing
the handle and assigning it to the ioctl output. They reserve handle
table capacity before taking that lock. If the manager has stopped by
the time BIND reaches publication, it returns `ENODEV`, leaves the
output and existing handles intact, and retires the new VA and GEM
reference after releasing both locks. Asahi also maps the buffer before
installing the handle and drops a rejected mapping after releasing the
handle table lock.
[Pinned Asahi timestamp BIND](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1217-L1232)

The sanitizer suite passed 128 simulated shutdown races after a
successful map and 185,000 timestamp ioctl checks across both ABIs. The
compiled baseline reproduced the publication bug. Both kernel builds,
82 test files and the independent lifetime review passed. The allocation
scan reproduced 178 baseline findings. A BIND that finishes publication
first can still return after shutdown. Cleanup of published mappings
across permanent teardown or manager replacement remains open. The full
source audit remains `not_equivalent`. No hardware tests or reboots ran.

Evidence for `9e54aacb83982c2a3617c00e32f34001c62cee4a` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-timestamp-commit-stop-20261118/`.
Each native build archive contains the executable and generated C, with
hashes verified after compression. The bundle passed full inventory
verification. `bundle.tar.gz` SHA-256 is
`6db23802111a185aa7ece04df529684db794f22b453fae8c4fac177d59f45dab`.

G13 timestamp mappings now stay with the GPU manager and UAT that
created them. Shutdown stops the ASC and drains that manager's timestamp
aperture under its lock, including maps whose BIND has yet to publish a
handle. Late file releases skip the stopped manager's retired aperture.
The file retains GEM backing until its captures retire. UNBIND, the
last detached capture and close release through the original manager.
Close releases uncaptured timestamps before waiting on unrelated queue
or VM cleanup. Asahi's mapping also retains its owning VM and UAT.
[Pinned Asahi mapping ownership](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs#L1233-L1242)

The sanitizer suites passed 128 file lifecycles across both ABIs, 64
aperture drains with replacement VA reuse and 185,000 timestamp ioctl
checks. Both kernel builds, 82 test files and the independent lifetime
review passed. All 17 compiled negative controls reached their designated
assertions. The allocation scan reproduced 178 baseline findings.
The scope covers already-bound timestamp files across ordered teardown
and replacement. General queue and VM reprobe, first BIND admission
on a stale file and native hardware quiescence remain open. The source
audit remains `not_equivalent`. No hardware tests or reboots ran.

Evidence for `845ba5df7fcd57a59c1b6d80fc17485fe3c05f1b` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-timestamp-teardown-20261118/`.
The complete archive passed inventory verification. `bundle.tar.gz`
SHA-256 is
`2b40fbb62fd04a02ac718aaf3c0703b6d1b69254c5099b56e16344683f0b5e2c`.

Each AGX DRM registration now publishes its own manager with the device.
The file copies that owner at construction, so even a first timestamp
BIND admitted before unplug reaches the original manager after replacement.
Once that manager has stopped, it returns `ENODEV` before reserving a VA
or writing the UAT. A BIND that wins the shutdown lock can still publish
on its original device. Asahi also maps through the GPU in its registration.
[Pinned Asahi timestamp BIND](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1188-L1218)

The sanitizer suite passed 128 simulated replacements during ioctl input
copy across both ABIs, with successful binds on the replacement opens.
The compiled global-manager counterexample reproduced the stale first BIND
bug. All 18 negative controls reached their designated assertions.
Both kernel builds, 82 test files and the lifetime review passed. The
allocation scan reproduced 178 baseline findings. General queue and VM
teardown and native validation remain open. The source audit remains
`not_equivalent`. No hardware tests or reboots ran.

Evidence for `511b0f663aa65d13996441e9da009cc3629067b5` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-timestamp-registration-20261118/`.
The complete archive passed inventory verification. `bundle.tar.gz`
SHA-256 is
`a65ab50de61a9f0d093e7c4d3c414a0d3b81a445a84303ef6ea9f3c891f15ea7`.

G13 shutdown now locks the original UAT before stopping the ASC. It
clears resident user TTBRs and invalidates their ASIDs while excluding
AP handoff callers. It wakes old slot waiters, refuses new roots, and
keeps outstanding job and staging leases in software until their last
release. Late releases cannot clear a replacement manager's roots.
Both submission ABIs reject a manager from another DRM registration.
Waits and deferred staging releases use the selected manager's UAT.

ASan and UBSan passed 64 simulated shutdown and replacement cycles
with leased and idle roots. Both submission ABIs passed a global UAT
swap during a slot wait. Three compiled negative controls caught a
missing invalidation, early lease disposal and a missed wakeup. Both
kernel builds, all 82 test files and the independent lifetime review
passed. The allocation scan reproduced 178 baseline findings.

This covers ordered shutdown and replacement. File-level queue and VM
owner routing, concurrent reprobe, recovery from an already wedged
handoff, and native quiescence remain open. The pinned source audit
remains `not_equivalent`. No hardware tests or reboots ran.

Evidence for `38415ca26bee5a8806d61b75240400a95dee115f` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-uat-slots-stop-20261118/`.
The complete archive passed inventory verification. `bundle.tar.gz`
SHA-256 is
`66e0b8c5888528c890c9f2a90bfd874afb25cf170d4c66553df2b222abc866e5`.

G13 opens now use their original DRM registration for queue and VM
creation, mapping checks, submission, and deferred teardown. After
ordered replacement, the old file can release its queues, mappings and
VMs through the old manager and UAT. VM creation on a stopped registration
returns ENODEV before allocating a context. An overlapping worker poll
requests a fresh pending snapshot. A late close enters the closing list
before requesting a reap, so it can be retried after the final pins drop.

Both kernel builds, 82 V test files and the ASan/UBSan close and submission
suites passed. The host tests cover replacement with separate UATs, a late
close during an active reap, and a final worker poll during a detached
pending snapshot. Three compiled controls caught wrong-owner queue close,
global UAT fallback and a missed worker poll. All 18 timestamp controls
passed. The independent lifetime review passed and the allocation scan
reproduced 178 baseline findings.

That revision has an ownership handoff gap if shutdown clears the
manager's quarantine list before the file adopts the failed constructor's
record. Concurrent teardown and reprobe, G17 resident-slot retirement,
and native quiescence remain open. The pinned source audit remains
`not_equivalent`. No hardware tests or reboots ran.

Evidence for `41aa1b93e344aff9c97b50da53c9ea1c8e58146e` plus the tested
patch is retained under
`/Users/alex/.local/state/vinix/omarchy-m1-g13-file-owner-20261118/`.
`bundle.tar.gz` SHA-256 is
`676a07075599f7ca8c7084bd0eea81f7b0c05a81c20c0971d920d89a13f654b0`.

Failed G13 queue construction now gives the file the quarantined record
under the manager lock. The file holds its own lock through adoption, so
it retains the VM and can free the record even when shutdown releases
the backing before the constructor returns. Both ioctl ABIs retain their
failure status and leave the requested queue name untouched.

The AArch64 and x86_64 kernels built, and all 82 V test files and the
sanitized constructor, close and async suites passed. The constructor and
ioctl fixtures each passed 64 shutdown handoffs. Host measurements found
zero retained blocks over 30,000 clean constructor failures and 6,000
render scratch layout rejections, including cleanup retries. The allocation
scan reproduced 178 baseline findings. The pinned audit still reports
`not_equivalent`. Concurrent reprobe and native validation remain open.

The restored archive passed the full inventory check for
`a8baabb2c567cd56a535594b76386310366285f0` plus `verified-source.diff`.
The evidence directory is
`/Users/alex/.local/state/vinix/omarchy-m1-g13-queue-adoption-20261118/`.
`bundle.tar.gz` SHA-256 is
`fdbdc3d6626aa4f5cb1e1246097a6e15645f9ccf03861623687be9ab0ba4c22e`.

G13 `GEM_CLOSE` now marks each existing binding of the removed object
under the file lock. If the VM is busy, those bindings still retire after
the object is re-imported. A partial unbind carries the close mark into both
surviving fragments. Later binds have their own lifetime. This follows the
pinned reference's rule that deferred handle close selects the bindings
present at close time. The change uses Vinix's existing idle VM cleanup
and retry paths. [Asahi deferred GEM cleanup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu/lifetime.rs#L581)

Both kernel builds, 82 V test files and the sanitized file-close and async
suites passed. The close fixture checks reimport during a busy VM, a later
bind to the same BO, a split old mapping and retry after a failed device
state check. Allocation counts match the prior build, including its 178
allowance findings. The pinned source audit remains `not_equivalent`.

The restored archive passed the full inventory check for
`c7d4661d9c6956b7f9a8da3ef233f7f75f130182` plus `source.diff`. Evidence is in
`/Users/alex/.local/state/vinix/omarchy-m1-gem-close-reimport-20261118.mgvxq3/`.
`bundle.tar.gz` SHA-256 is
`b5dbe0fd5b3ab22c8eaefeaa2a6899fdbf068613ed5d61f19688d5631936b02d`.

Modern G13 `QUEUE_CREATE` now uses the lowest free ID. A failed create
returns its reservation even when firmware backing needs cleanup.
`QUEUE_DESTROY` returns the ID immediately and frees the logical record.
Existing captures and accepted jobs retain the original physical queue
and its VM while the worker retires it. Reusing the name selects a new
physical owner. This follows the pinned Asahi namespace policy. [Asahi queue create and destroy](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs#L1277)

The registered ioctl fixture passed same-name replacement with the old
capture still held and an injected old-owner retirement retry. The
file-close and async sanitizer suites, 82 V test files, and both kernel
builds passed. A host probe ran 6,000 render scratch rejections with no
retained blocks or consumed names. The allocation scan repeated 178
baseline findings. The pinned source audit remains `not_equivalent`.

The verified archive for `b60d2eacbaefb8608b81bf6c2c40fbf62c19556c` plus `source.diff` is in
`/Users/alex/.local/state/vinix/omarchy-m1-g13-queue-names-20261118.0j8Zqy/`.
`bundle.tar.gz` SHA-256 is
`0ba28b05fc3c3a06731a677f279dde36f8df8bbd701541d9defb90b4b49b2fb6`.

The G13 worker now retires mappings selected by `GEM_CLOSE` after their
VM's last in-flight pin drops. The worker retries a failed device-state
check from the already-cleared PTE and clears the pending flag when
retirement succeeds. VM names and unrelated bindings remain available.
This applies the pinned driver's deferred-cleanup policy to Vinix's
existing VM pin and worker model. [Asahi VM lifetime cleanup](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu/lifetime.rs#L646)

The file-close fixture passed independent retirement on two visible VMs,
including a device-state failure and retry without a second PTE removal.
Both kernel builds, 82 V test files, and the file-close and async
sanitizer suites passed. The allocation scan matched the 178 baseline
findings. The pinned audit still reports `not_equivalent`.

The restored archive passed inventory verification for
`fc45744d338b743448b1195be27fd64eebd350c6` plus `source.diff`. Evidence is in
`/Users/alex/.local/state/vinix/omarchy-m1-gem-close-worker-20261118.fDORnE/`.
`bundle.tar.gz` SHA-256 is
`59f3a5d6c28a83ee36a493f4943a0be2b7f4051137368764143d69a392cd61ef`.

G13 timestamp `BIND` now returns `ENOMEM` when the VA record or its
pointer table cannot be allocated. Both allocations finish before the
heap changes its hole order or the driver installs PTEs. A full 64 MiB
aperture returns `ENOSPC`, and releasing a reservation makes its range
available again. The pinned driver also allocates its DRM MM node
fallibly. [Asahi timestamp mapping](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gpu.rs#L1472-L1485) [DRM MM node allocation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/rust/kernel/drm/mm.rs#L249-L269)

Both kernel builds, 82 V test files, and the sanitized file-close and
heap fixtures passed. Fault injection checked the first record and table
allocations and a later table expansion while reservations were live.
The host probes measured zero retained blocks and bytes after 30,000
allocation cycles and after freeing an 8,192-entry table. The allocation
scan matched its 178 baseline findings. The pinned source audit remains
`not_equivalent`. This round used host checks and cross-builds.

The restored archive passed inventory verification for
`dbac3215706c6eab19de1457e38255c6cc324e9a` plus `source.diff`. Evidence is in
`/Users/alex/.local/state/vinix/omarchy-m1-timestamp-heap-20261118.XIVRNm/`.
`bundle.tar.gz` SHA-256 is
`0cba7d7b953fe9113daedae7331587f3274c93a91a1b62494ede03a1ffded179`.

`GEM_CREATE` now returns `ENOMEM` when the GEM object record cannot be
allocated. The shared constructor reserves metadata before allocating
or retagging backing pages. It frees the record if either later step
fails, and advances the mmap offset and publishes the handle only after
both steps succeed. The pinned driver also reserves its GEM record
fallibly before initializing its backing. [Asahi GEM creation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/gem.rs#L280-L311) [DRM shmem constructor](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/rust/kernel/drm/gem/shmem.rs#L340-L372)

The sanitized CPU-cache fixture passed 300 injected metadata refusals,
confirmed handle and mmap offset reuse on retry, and checked metadata
release after backing and cache retag failures. The private GEM and
file-close fixtures, 82 V test files, and both kernel builds passed.
The allocation scan removed one implicit site on each architecture and
reported 177 existing findings. The pinned source audit remains
`not_equivalent`. Validation used host checks and cross-builds.

The restored archive passed inventory verification for
`5f25413bb3bac398aecb8e9c834f2a159c91a675` plus `source.diff`. Evidence is in
`/Users/alex/.local/state/vinix/omarchy-m1-gem-metadata-20261118.BTXykY/`.
`bundle.tar.gz` SHA-256 is
`e27181112076214ec248873d4f65b225fc84786cf31d20e52747db6528d9d33e`.

AGX `GEM_CREATE` now reserves space in the file's handle table before
constructing the object. If the first table allocation or later growth
fails, the ioctl returns `ENOMEM` with the existing handles and request
fields intact. The native and software backends hold the file lock from
reservation through publication. The pinned DRM core also reserves its
handle entry fallibly. This revision assigned handle numbers from the global
GEM table. [Pinned DRM handle creation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_gem.c#L479-L535)

The sanitized ioctl fixture passed 256 injected allocation failures
across the two native ABIs. It checked creation with spare capacity,
retry after growth refusal, and release of both replaced and final
buffers. The CPU-cache fixture, 82 V test files, and both kernel builds
passed. The allocator scan matched 177 existing findings. The pinned
source audit remains `not_equivalent`. Validation was offline.

The restored archive passed inventory verification for
`0bef0ef7aa836c50932ecc82ec50a07c4e106b27` plus `source.diff`. Evidence is in
`/Users/alex/.local/state/vinix/omarchy-m1-gem-handle-storage-20261118.sCpXgC/`.
`bundle.tar.gz` SHA-256 is
`516036194cad54d0941ff9c9e058fa19c0237f06eba8b804a33fbcabc067cda5`.

G13 opens now allocate the lowest available nonzero GEM handle in each
file, matching the pinned DRM allocator. Both ABIs use the same file
table from open, so PRIME imports issued before ABI selection keep their
names. Repeated imports return the existing name. Closing a handle makes
its number available while existing mappings and exports retain the
original object. Vinix's global backing-object limit still applies.
[Pinned DRM handle allocation and release](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_gem.c#L384-L535)

The sanitized fixture passed 64 pairs of legacy and modern files. It
covered early PRIME import, duplicate and failed imports, reuse with a
full table, and independent mmap offsets and export owners. It also
passed the existing 256 table allocation failures and timestamp
registration races with the new names. Both kernel builds, the CPU-cache
fixture and 82 V test files passed. The allocation scan matched its 177
baseline findings. The pinned offline audit remains `not_equivalent`.

The restored archive passed inventory verification for
`d4214b5cf55d21c1c90ad6a274f3bb44fa32fc14` plus `source.diff`. Evidence is in
`/Users/alex/.local/state/vinix/omarchy-m1-gem-file-names-20261118.iDELzd/`.
`bundle.tar.gz` SHA-256 is
`14fa9d5cb971a3a26c2c329185130c895854020739eab729a86da5b1939af400`.

Base M1 G13 can use the AIC mailbox receive interrupt with a timed poll
fallback. [RTKit mailbox receive IRQ](m1-agx-rx-irq.md)

G13 receive doorbells drain FWLog, KTrace and Stats before handling firmware
events and later RTKit messages. [Firmware receive order](m1-agx-rx-doorbell.md)

G13 ASC transmits use the 500 ms FIFO wait from the pinned driver.
[RTKit mailbox transmit timing](m1-agx-rtkit-transmit.md)

G13 advances boot on IOP acknowledgement and checks both power states for
application endpoint starts and sends. [RTKit IOP acknowledgement](m1-agx-rtkit-iop-ack.md)

Both G13 ABIs continue after discovery reply timeouts and retry an unsent
endpoint start once. [RTKit management send failures](m1-agx-rtkit-management-send.md)

G13 follows firmware-led RTKit startup with separate deadlines for endpoint
discovery and power acknowledgements. [RTKit boot handshake](m1-agx-rtkit-boot.md)

G13 continues boot and runtime receive processing after a Syslog or IOReport
acknowledgement timeout. [RTKit log acknowledgement handling](m1-agx-rtkit-log-ack.md)

G13 keeps RTKit boot and receive processing going after a first-buffer
failure. [RTKit initial buffer failure handling](m1-agx-rtkit-first-buffer.md)

G13 acknowledges the full wrapping OSLog counter after negotiating its
channel-zero buffer. [RTKit OSLog acknowledgements](m1-agx-rtkit-oslog.md)

G13 prepares each RTKit allocation for firmware before publishing its address
and reads bounded Syslog records before acknowledgement.
[RTKit Syslog and buffer preparation](m1-agx-rtkit-syslog.md)

RTKit resends the existing Syslog, IOReport and OSLog buffer addresses for
matching requests, including after a mailbox timeout.
[RTKit shared-buffer retries](m1-agx-rtkit-buffer-retry.md)

RTKit ignores unknown crash notifications and decodes crash time, mailbox
history and exception registers on both G13 ABIs.
[RTKit crash-log decoding](m1-agx-rtkit-crash-parser.md)

G13 RTKit copies the crash log before parsing and serializes system buffer
requests with shutdown. [RTKit crash-log snapshot](m1-agx-rtkit-snapshot.md)

G13 Event, KTrace and Stats reads hold the manager lock through acknowledgement
so shutdown can release the rings safely. [Receive ring teardown](m1-agx-rx-lifetime.md)

G13 firmware logging uses six descriptor rings and separate payload storage.
[Firmware log channel](m1-agx-fwlog.md)

Modern G13 VM_BIND reserves its batch buffer before the user copy can report
a bad pointer. [VM_BIND staging](m1-agx-vm-bind-staging.md)

Modern G13 SUBMIT restores the normal 2 ms firmware idle delay before queue
lookup. [Submit idle delay](m1-agx-submit-idle-delay.md)

Modern G13 attachment records accept index-zero barriers for absent prior
events. [Attachment record barriers](m1-agx-attachment-barriers.md)

Modern G13 SUBMIT checks device loss after staging and before packet parsing.
[Modern submit device errors](m1-agx-modern-submit-device.md)

Both G13 submit ABIs publish output fences after the manager accepts the
batch. [Output fence publication](m1-agx-output-publication.md)

Both G13 submit ABIs hold a single firmware operation for each batch.
[Firmware operation ownership](m1-agx-operation-ownership.md)

G13 captures prior queue events for index-zero barriers before VM
admission. [Prior events at admission](m1-agx-prior-event-admission.md)

Queues that share a G13 VM now serialize admission to the UAT slot
allocator. [Per-VM binding admission](m1-agx-vm-binding-admission.md)

G13 preserves slot release order across root removal and invalidates the
ASID once after publishing a replacement root. [UAT slot replacement](m1-agx-uat-replacement.md)

G13 serializes same-queue job preparation through the UAT wait and notifies
one waiter when a slot is released. [Queue admission](m1-agx-queue-admission.md)

Both G13 submit ABIs now wait interruptibly for an eligible UAT slot.
[G13 UAT slot admission](m1-agx-slot-wait.md)

G13 now reuses idle hardware slots after the last prepared job releases its
backing. [G13 UAT slot leases](m1-agx-slot-leases.md)

G13 VM creation uses a growable per-file namespace. The first job preparation
assigns a hardware slot. [VM admission and slot assignment](m1-agx-dormant-vms.md)

Final AGX VM teardown now reclaims the host records and both VA heap tables
after root invalidation. [VM reclamation](m1-agx-vm-release.md)

G13 records the published UAT slot in each render and compute job for command
construction and fault recovery. [Firmware slot routing](m1-agx-job-asid.md)

G13 publishes a VM's UAT root during its first render or compute job
preparation. [Deferred UAT root publication](m1-agx-deferred-uat.md)

Native VM IDs now belong to the open DRM file. A detached name can be reused
while an old queue retains its hardware context. [VM names](m1-agx-vm-names.md)

Native VM creation now allocates one 16 KiB page of backing for the dummy UAT
mapping. [Dummy page backing](m1-agx-vm-dummy-page.md)

The native base-M1 `DRM_IOCTL_VERSION` reply matches the packaged driver
identity read by Mesa during device open.
[DRM version reporting](m1-agx-drm-version.md)

Base M1 now selects the packaged soft-fault default in both G13 firmware
layouts and reports it to Mesa through `GET_PARAMS`.
[Soft-fault initialization and capability](m1-agx-soft-faults.md)

The modern packet path accepts the pinned Mesa base-M1 command sizes and
requests a stamp flush on the final render and final compute command in
each batch. [Mesa packet and stamp-flush checks](m1-agx-mesa-packets.md)

The native base-M1 DRM device now advertises `DRM_CAP_SYNCOBJ_TIMELINE`.
Userspace can discover the shared timeline through the standard GET_CAP probe.
[Timeline capability reporting](m1-agx-timeline-capability.md)

Native G13 legacy and modern submissions now share DRM timeline fence chains.
Both formats can consume points published by the other format or by DRM. The
legacy path reserves chain nodes before job preparation.
[G13 timeline interoperability](m1-agx-legacy-chain.md)

DRM WAIT and sync-file requests now propagate deadline hints to captured
G13 fences. Each queue fence keeps the earliest signed hint.
[Fence deadline hints](m1-agx-wait-deadlines.md)

DRM syncobj eventfd now notifies a counter when a timeline point becomes
available or completes. Captured fences retain their notifications through
handle and descriptor close. [Syncobj eventfd notifications](m1-agx-syncobj-eventfd.md)

Sync-file import and export now accept the timeline point in the 24-byte
descriptor request. The original 16-byte requests still accept point-zero
operations. [Timeline sync-file descriptors](m1-agx-timeline-sync-file.md)

Binary WAIT snapshots every syncobj before registering for new submissions.
Registration observes the current fence after any transient fence from that
pass has been cleared. [Binary WAIT capture ordering](m1-agx-binary-wait-capture.md)

Binary and timeline WAIT accept the request sizes from before `deadline_nsec`
and follow the packaged DRM core's direction and copy rules.
[DRM syncobj WAIT request framing](m1-agx-wait-wire.md)

The file worker can visit unrelated queues after the first 128 waiting or
retiring queues. A batch still waits behind unpublished work on its own queue.
[Per-queue publication FIFO](m1-agx-queue-poll.md)

[32-bit G13 fence numbering](m1-agx-fence-ordinals.md) starts each queue's
finished fence sequence at one and wraps through zero. The
[independent fence fix](m1-agx-independent-fences.md) preserves distinct
dependencies across reverse retirement and wrap.

The [pre-hardware audit](m1-agx-prehardware-20261117.md) matched all twelve
registered modern ioctl words against the packaged C header and identified the
reverse-retirement regression in `f183daa00`. Vinix still bundles a different
Mesa revision from Omarchy. The earlier
[dependency qualification](m1-agx-job-dependencies.md) describes the initial
64-bit reduction and its reference scope.

Preceding increment: [GEM advice for resident private objects](m1-agx-gem-advice.md)
(2026-11-17). The twelfth modern request records private-object advice, returns
retained contents and preserves reference ownership across handle removal.
All 20,480 resident transitions match the pinned shmem helper; sanitizer,
retention and native-build checks pass. Purging/backing integration and full
driver parity remain incomplete.

Preceding correction: [independent fake AGX fence contexts](m1-agx-fake-fences.md)
(2026-11-17). Fake workers can retire out of order even on one queue; each job
now gets a unique context so merging preserves every pending dependency.
Exhaustion unwinds acquired pins before output effects. Sanitized completion
permutations and transaction regressions pass. Full parity remains incomplete;
the generic timeline capability stays disabled.

Preceding increment: [DRM timeline destination transfers](m1-agx-timeline-transfer.md)
(2026-11-17). Transfers flatten chains/arrays, deduplicate pending contexts and
publish cumulative destination points. Flat-array readiness, errors and sync-file
records are supported. Queue identities prevent cross-queue dependency loss;
explicit 64-bit atomic errors preserve ARM signs. All 8,640 comparison outcomes
match pinned Linux. Reclamation, interoperability and native/hardware qualification
remain open; the generic timeline capability stays disabled.

Preceding increment: [DRM transfers to binary syncobjs](m1-agx-binary-transfer.md)
(2026-11-17). Source points transfer as stable fences, with submission waits and
destination identity retained through name reuse. All 10,752 compared outcomes
match pinned Linux. An explicit stack capture avoids V's implicit heap copy.
Timeline-destination merging remains unsupported and the generic timeline
capability stays disabled. Full driver/hardware parity remains incomplete.

Preceding increment: [generic DRM timeline WAIT](m1-agx-timeline-wait.md)
(2026-11-17). Initial point snapshots precede future-point registration;
captured fences survive reset and name reuse. Every exit detaches borrowed
captures before freeing storage. All 21,952 pinned Linux poll outcomes match.
Transfer, native scheduling/deadlines, reclamation and broader driver/hardware
qualification remain open; the generic timeline capability stays disabled.

Preceding increment: [generic DRM timeline SIGNAL](m1-agx-timeline-signal.md)
(2026-11-17). All object/point snapshots and chain reservations precede
publication. Signals use a permanent completed payload and retain cumulative
predecessors. Binary completions stay private. Timeline wait/transfer, allocator
and timestamp policy, reclamation and hardware qualification remain open.

Preceding increment: [generic DRM timeline QUERY](m1-agx-syncobj-query.md)
(2026-11-17). Queries distinguish completed progress from the last submitted
point, snapshot all object identities before output and preserve partial-copy
ordering. The generic timeline capability remains disabled pending wait,
signal and transfer. Full parity remains incomplete.

Preceding increment: [modern cumulative timeline chains](m1-agx-timeline-chain.md)
(2026-11-17). Modern outputs now publish cumulative roots and accept zero,
duplicate and decreasing points; inputs preserve snapshots and resolve retired
prefixes. Exported sync-file info unwraps leaves. Legacy interoperability,
metadata reclamation, allocator/timestamp policy and hardware qualification remain.

Preceding increment: [modern sync lists beyond 64 records](m1-agx-sync-storage.md)
(2026-11-17). Modern SUBMIT uses checked, fallible spans for larger input/output
lists; pending work owns an independent dependency copy until retirement.
Legacy limits, cumulative-chain gaps and allocator-policy differences remain.

Preceding correction: [validate render scratch after queue construction](m1-agx-queue-scs.md)
(2026-11-17). Modern G13 queue creation now preserves VM/constructor error
precedence before refusing a nonzero layout. Failed rollback retains its graph,
VM and ID through the existing orphan retry path; no logical name is published.

Preceding correction: [preserve modern timeline input point zero](m1-agx-sync-zero.md)
(2026-11-17). Zero now waits on the captured fence instead of dropping the
dependency. Unsigned point-map behavior and cumulative-chain gaps remain
separate; this correction does not certify full timeline equivalence.

Preceding increment: [registered modern native ioctls](m1-agx-modern-dispatch.md)
(2026-11-17). G13 now registers eleven modern operations alongside its legacy
interface, with per-file ABI selection, flat-packet submission, combined sync
records and snapshotted batched VM binding. Queue USC state and timestamp
objects reach the shared scheduler. Mesa migration, purge advice, complete
timeline/backing semantics and hardware acceptance remain open.

The [preceding parity recheck](m1-agx-signoff-20261117.md), on 2026-11-17,
compared fresh remote default-branch checkouts. Both committed and working-source
audits reported **not_equivalent**, with 15 differing selected ABI facts before
the modern registration increment. Those legacy declarations are
retained for compatibility; the auditor now explicitly scopes that comparison
and retains the modern declarations separately. The recheck corrected stale
admission/backlog entries below and separated G17-only memory limits from the
base-M1 requirements.

Preceding kernel increment: [logical queue-record reclamation](m1-agx-workqueue-records.md)
(2026-11-17). Native and fake file owners now free logical queue metadata after
destruction returns and their owner rows are removed. Pending fake completions
retain their file/VM pins through their last queue access. Host close retention
falls from 10,000 records per 10,000 closes to zero. Native slab rates remain
unmeasured. The [final G13 queue-record reclamation](m1-agx-queue-records.md) report
retains the separate firmware-resource metadata fix and original evidence
(2026-11-17). Close and both file-owner reapers reclaim released records
after their last captures and ownership rows are gone. Mapping failures and
manager absence retain metadata for retry. The [failed queue-constructor record reclamation](m1-agx-queue-unwind.md)
report retains the separate unreturned-record fix and original evidence.
The [deferred G13 context invalidation](m1-agx-context-defer.md)
report retains the release-order snapshot and allocator-borrow evidence.
Its ownership comparison is corrected: Asahi's context objects transitively
retain TVB backing and VM allocators. Vinix also retains extra queue graph state.
The [acknowledged context retirement](m1-agx-context-retire.md)
report retains the earlier command, retry and captured-prefix evidence.
The [deferred private collection during teardown](m1-agx-teardown-gc.md) report
retains the earlier private-range policy and its evidence. Initialization and
stopped cleanup retain explicit drains. The [unpublished reservation cancellation](m1-agx-heap-cancel.md)
report retains the mapping-failure correction and its original evidence.
The [G13 allocation-pressure policy](m1-agx-heap-pressure.md)
report retains the implicit-GC pressure correction and its original evidence.
The [returning worker scheduling](m1-agx-worker-reschedule.md) report retains
the G13/G17/fake scheduler correction and its original evidence. The
[UAT completion polling](m1-agx-uat-poll.md) report retains the separate
firmware-control wait correction and its original evidence. Native scheduling,
deferred context invalidation, allocator backing/accounting and native
performance remain different or unqualified.
The [firmware-cache barrier and threshold collection](m1-agx-heap-gc.md) report
retains the captured-prefix collection comparison and its original evidence.
The [shared heap release policy](m1-agx-release-policy.md) report retains the
immediate-release class comparison and its evidence.
The [bounded FIFO deferred collection](m1-agx-garbage-fifo.md) report retains
the count-limited collection and pending-garbage evidence.
The [GPU hole insertion history](m1-agx-hole-order.md) and
[best-fit GPU virtual-address reuse](m1-agx-heap-reuse.md) reports retain their
original evidence.
Modern ioctl/Mesa integration and remaining stage backing/event destruction
are incomplete. The [GPU heap collection below live allocations](m1-agx-heap-collect.md),
[GPU heap pointer-buffer reclamation](m1-agx-heap-capacity.md),
[GPU heap alignment-padding reclamation](m1-agx-heap-padding.md),
[checked GPU heap allocation bounds](m1-agx-heap-bounds.md),
[GPU heap metadata reclamation](m1-agx-heap-records.md),
[completion before deferred cleanup](m1-agx-completion-order.md),
[compute event admission credit](m1-agx-compute-credits.md),
[render event admission credit](m1-agx-event-credits.md),
[render-stage timestamp ownership](m1-agx-stage-timestamps.md),
[independent render ring retirement](m1-agx-render-retirement.md),
[native AGX error publication](m1-agx-native-errors.md),
[per-command timestamp retirement](m1-agx-command-timestamps.md),
[pending submission timestamp ownership](m1-agx-pending-timestamps.md),
[resolved timestamp preparation inputs](m1-agx-timestamp-inputs.md),
[timestamp capture ownership](m1-agx-timestamp-capture.md),
[modern packet command adapter](m1-agx-packet-input.md),
[failed queue construction cleanup](m1-agx-orphan-queue.md),
[VM namespace removal and retained ownership](m1-agx-vm-detach.md),
[captured G13 queue ownership](m1-agx-queue-references.md),
[queue namespace removal](m1-agx-queue-detach.md),
[base M1 render tiling comparison](m1-agx-tiling.md),
[GEM WRITEBACK and CPU cache policy](m1-agx-gem-cache.md),
[complete start/finalize field comparison](m1-agx-microseq-fields.md),
[timestamp instruction pair binding](m1-agx-timestamp-pair.md),
[complete fragment fields and auxiliary defaults](m1-agx-fragment-fields.md),
[vertex/compute common fields](m1-agx-work-tails.md),
[fragment layouts and depth insertion](m1-agx-fragment-layout.md),
[13.5 parameter and scratch offsets](m1-agx-fragment-tail.md),
[compute finalizer command flag](m1-agx-compute-finalize.md),
[versioned single-cluster vertex start](m1-agx-vertex-marker.md),
[G13 submissions after device loss](m1-agx-submit-device.md),
[zero-length BIND before BO lookup](m1-agx-bind-zero.md),
[timestamp-object validation and lookup order](m1-agx-timestamp-bind.md),
[global parameter queries after device loss](m1-agx-param-device.md),
[global GET_PARAMS copy behavior](m1-agx-param-copy.md),
[BIND overlap replacement and preparation](m1-agx-bind-replacement.md),
[UNBIND ranges and surviving mappings](m1-agx-unbind-range.md),
[GEM-create size errors](m1-agx-gem-size.md),
[repeated single-page bindings](m1-agx-single-page.md),
[BIND buffer lookup order](m1-agx-bind-bo-order.md),
[bind VM lookup and global validation](m1-agx-bind-vm-lookup.md),
[submit queue lookup before staging](m1-agx-submit-lookup-order.md),
[VM and queue identity lookup errors](m1-agx-identity-lookup.md),
[submission syncobj lookup errors](m1-agx-sync-lookup.md),
[descriptor reservation during export](m1-agx-export-reservation.md),
[timeline lookup at UINT64_MAX](m1-agx-timeline-boundary.md),
[deadline hints for sync-file leaves](m1-agx-sync-file-deadline.md),
[single-leaf information queries](m1-agx-sync-file-info.md),
[sync-file completion readiness and wakeups](m1-agx-sync-file-poll.md),
[binary sync-file import validation](m1-agx-sync-file-import.md),
[opaque syncobj descriptor sharing](m1-agx-syncobj-sharing.md),
[syncobj namespaces beyond the fixed table](m1-agx-syncobj-namespace.md),
[fallible syncobj creation before publication](m1-agx-syncobj-create.md),
[binary syncobj SIGNAL](m1-agx-syncobj-signal.md),
[binary syncobj reset](m1-agx-syncobj-reset.md),
[binary wait storage beyond 64 handles](m1-agx-wait-storage.md),
[first-submission capture and interruption](m1-agx-wait-capture.md),
[binary wait snapshots](m1-agx-binary-wait.md),
[fence completion status](m1-agx-fence-completion.md),
[native fragment TIB sizing](m1-agx-render-tib.md),
[native driver VM geometry](m1-agx-vm-geometry.md),
[G13 queue priority and failed-create ownership](m1-agx-queue-priority.md),
[VM-private buffer isolation](m1-agx-private-bo.md),
[GPU mapping permissions](m1-agx-gpu-permissions.md),
[user mapping retirement](m1-agx-user-map-retirement.md),
[prepared backlog](m1-agx-prepared-backlog.md),
[batch publication](m1-agx-batch-publication.md) and [admission](m1-agx-batch-admission.md)
reports retain their original evidence.

## Offline sign-off audit, 2026-11-14

Result: **not equivalent; no 100% parity sign-off**. This conclusion is available
without a hardware boot. Fresh checkouts of Omarchy
`663aff7b9943aeff67809d106399fb406410798c` and omarchy-pkgs
`88d516f3e3b7ce66b02e613f04b89152473a25e3` still select the same Linux-Aurora
kernel pin above. The Mesa package selects 26.3.0 development source
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`.

The new [offline source audit](../tools/agx-re/m1parity/README.md) compares
actual declarations from both trees. It found 16 differing selected facts,
including:

| Contract | Vinix | Packaged Asahi reference |
| --- | --- | --- |
| `GET_PARAMS` request | 32 bytes; pointer at offset 16 | 24 bytes; pointer at offset 8 |
| `SUBMIT` request | 56 bytes; separate sync arrays and command descriptors | 40 bytes; combined sync array and flat command buffer |
| VM binding request | 48 bytes; one operation | 24 bytes; pointer/stride/count for a batch |
| No-barrier sentinel | `0xffffffff` | `0xffff` |
| VM read/write permission bits | `1` / `2` | `2` / `4` |
| Maximum hardware commands per submit | 2 | 64 |
| DRM command numbers, including base `0x40` | `GET_TIME=0x49`, `SUBMIT=0x48` | `GET_TIME=0x41`, `SUBMIT=0x4a` |

The command numbers in this table omit the full ioctl's size/direction encoding.
These are concrete incompatibilities, not an exhaustive count or a coverage
percentage. Changing the constants alone would break the existing Mesa-facing
contract; the kernel ABI, submission handling and matched userspace need to
migrate together. The broader source gaps remain listed below.

The audit checks the immutable package pin, clean reference inputs, source
hashes and selected firmware contracts. Unknown or missing declarations fail
the audit. Matching selected facts alone yields `unverified`, never full
equivalence. Its current result exits 1; provenance or source-gate failures exit
2. The Make entry point also propagates the nonzero result. No hardware access,
SSH, guest boot or reboot was performed.

Validation passed: audit/contract/layout unit tests; event, TLB and recovery/TVB
sanitizer fixtures; G13 ABI translation, work-command layouts, t8103 OPP and the
pure VM request tests. The ABI/layout/OPP probes initially hit a host V module
cache failure while compiling unused privileged routines. Their uncached
monolithic builds passed; both attempts are retained. This audit changes host
tooling and documentation, and claims no new kernel build or GPU execution.

The retained source baseline is Vinix
`76567c7aa424a1d26f2b5336035583c158d1957f` plus the audit tooling, bound by
individual source hashes. Sources, reports, native probes and validation logs
are retained in
`/Users/alex/.local/state/vinix/omarchy-m1-offline-audit-20261114/evidence/`.
The sibling `inventory.json` has SHA-256
`dfc33f94c655d9fba1e4ec529302bd2757ff266fe6ac97107ba51c9170692f50`.
The retained `validation/evidence-checker.v` checks the complete named bundle
using `check-inventory EVIDENCE INVENTORY`. This protects evidence integrity;
it does not certify full driver equivalence.

## Additional logic implemented

- **Page and range TLBI.** Ported the reference's 16 KiB operand encoding,
  including scale changes and advancing BADDR between full chunks. Mapping
  edits now use range invalidation; global firmware mappings still use full
  invalidation. Both sides retain the full-system barriers.
- **Workqueue retirement.** Firmware `gpu_doneptr` and host `cpu_freeptr`
  have separate owners. Completed commands now publish their last occupied
  slot to `cpu_freeptr`. Logical command ordinals prevent reverse reaping
  from rolling it backwards when the modulo ring pointer wraps.
- **TVB growth.** GrowTVBAck carries the current 64-bit firmware halt counter
  at offset `0x18`.
- **Fault and timeout recovery.** Both firmware ABIs decode their pending
  stamp records, classify culprit/killed work, preserve completed jobs, wait
  for the halt handshake, and acknowledge resume. Cross-VM faults are reported
  as killed work. Resources remain owned until firmware completion stamps
  advance; notification alone never permits freeing a command.
- **Channel recovery.** A recoverable channel error locates its queue,
  records its error and sends RecoverChannel, waiting for consumption.
- **Error reporting.** Job results preserve fault diagnostics and timeout,
  killed and channel-error status. Fences distinguish timeout, cancellation,
  no-device and unknown errors. Shutdown retains stop-before-free ordering.
- **Generated offsets.** Pending-submission and pending-stamp offsets now
  come from the existing V layout generator at both firmware ABIs.
- **Event slot reuse.** Driver stamps start at `slot << 24`, as in the
  reference. Releasing and reacquiring a slot preserves both firmware counters;
  the next command advances from the last observed driver value. An explicit
  armed state distinguishes a newly owned slot from a command whose counter
  wrapped to zero.
- **TVB feedback growth.** Before allocating a render scene, firmware's
  recorded maximum page use is sampled and its reset is requested. The
  reference's policy grows when 2x usage exceeds current capacity and targets
  rounded-up 3x usage, capped at the non-memoryless block limit. Calculations
  use 64 bits to handle every raw 32-bit statistics value.

Corrupt ring indices, failed recovery acknowledgments and unexplained halts
remain fatal. The worker drains a queued fault notification before treating
its halt as unexplained. Recovery and retirement introduce no new kernel
allocations. TVB feedback uses the existing growth and cleanup path; these
changes retain the existing object ownership model.

## Remaining differences

This inventory distinguishes implemented selected contracts from known gaps
and unverified behavior. Passing a source gate does not certify a complete row.

| Area | Vinix versus the packaged reference |
| --- | --- |
| Userspace ABI | Native G13 registers the legacy interface and twelve modern extensible operations, selected per file. Modern flat packets and combined syncs reach the scheduler. GEM_MADVISE records private-object advice with resident contents; complete request/sync/backing semantics and matched Mesa integration remain incomplete. |
| Submission scheduling | Vinix prepares up to 64 mixed render/compute commands through either native interface. In-batch and initial cross-submission dependencies use firmware prefixes. Later batches pipeline after older publication. The file worker tracks publication FIFO per queue without a fixed lookup limit. Whole-batch ring/event readiness and atomic publication are implemented. Finished fences use wrapping 32-bit per-queue numbers. Private input copies keep each independent native fence and the latest fence per ordered context. Own-queue native fences are elided. The pinned Asahi source documents that compute can finish before earlier render work on the same context. Vinix keeps both fences in that case. Full scheduler policy and timeline-chain equivalence remain open. [Asahi queue submission](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs#L723) |
| Queue destruction | G13 queue names disappear immediately. A modern file can reuse the ID before the original queue drains. Submission captures and accepted work retain their physical queue through copying, callbacks and final retirement. Invalidation failures retain backing. |
| VM destruction | VM names disappear independently of queues and jobs. Existing queues retain physical contexts. Idle user bindings use acknowledged teardown, and failed invalidation retains backing. Contexts retire after every owner ends. Native close timing, reservation scheduling and firmware-slot eligibility still differ. |
| Failed queue construction | The constructor transfers a quarantined record to its file before releasing the manager lock. The file adopts it even if shutdown has released the backing. Modern G13 returns the ID at failure. The worker retries unpublished backing and releases its VM ownership after cleanup. |
| Render scenes | Multiple prepared and published scenes retain shared backing and conditional binding. Commands and batches on one queue may overlap; individual commands wait for their explicit firmware dependencies. |
| Command ring capacity | Compute and both render subqueues count host-unretired command positions and require Asahi's spare entry before publication. Firmware consumption alone does not release host capacity. |
| Event publication capacity | Publication applies Asahi's strict spare-slot rule to the last-published/host-completed stamp delta. Whole-batch readiness checks all three pipes before publication. Preparation grows beyond the inline 127 tickets through owned overflow blocks; it is no longer capped at 127. These selected contracts do not establish complete scheduler equivalence. |
| TVB ownership and growth | Staged extension, scene-bound slots and shared tail-pointer backing are implemented below. Full scheduler backpressure and the remaining render defaults still require comparison. |
| VM binding | Vinix supports legacy single operations and modern strided batches, copied completely before mutation, with sequential-prefix error semantics. Modern G13 matches Asahi's scratch size bound and allocation-before-copy order. Contiguous/repeated backing, idle overlap replacement and range splitting are implemented. Busy-VM refusals, scatter backing and DRM GPUVM/reservation-fence integration still differ from the reference. |
| GEM and memory accounting | Vinix records private-object GEM_MADVISE and reports resident contents. Purge/repopulation, shmem/scatter backing, device/client accounting and full reservation-fence behavior remain different or unqualified. The reference's admission limits and creator-RSS attribution are enabled only for G17, so those limits are not a base-M1 blocker. |
| Timestamp UAPI | Registered modern SUBMIT now resolves compact per-command timestamp objects into all three engines. Capture, independent retirement and modern nanosecond GET_TIME are implemented. Native firmware execution and units still require hardware acceptance. |
| Power management | Modern G13 SUBMIT restores the packaged 2 ms idle delay on both firmware layouts. Asahi's debug delay overrides and broader reset and suspend/resume behavior remain open. |
| M1 family | The native path configures base M1/t8103. The reference also supports t6000/t6001/t6002 M1 Pro/Max/Ultra, including clustering and multiple dies. |
| Telemetry | G13 firmware logging matches the packaged descriptor and payload layout. Vinix prints numbered log levels through its kernel logger. Linux severity filtering and the full firmware statistics/debug interface remain open. |
| Complete wire comparison | Existing tests cover selected InitData and work-command contracts. Every remaining field/default still needs independent comparison; a matching structure size is insufficient. |
| Userspace integration | Vinix's bundled Mesa is 25.0.5. Omarchy packages a newer matched Mesa/DRM stack. Driver ABI modernization and userspace migration must be verified together. |
| Hardware acceptance | No native Vinix boot, recovery, compute/render result, concurrent lifecycle or performance result was obtained for this change. |

This inventory does not certify unchecked behavior as equivalent. Closing the
ABI and scheduler rows is a substantial remaining port, not a rename or a
package-selection change.

### Packaged wire protocol components

The first ABI migration component derives all 28 wire records from the
packaged `asahi_drm.h` at Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. The native C oracle checks every
record size and field offset, the twelve request numbers, and command,
permission and render flag constants. An allocation-free flat-packet reader
handles 64 hardware commands, synthetic attachment state, independent
subqueue barriers, short records and unsupported tails. Generic DRM framing
can select a negotiated ABI and apply extensible request copying.

These components are not yet registered by the native Asahi driver. Its
active Mesa 25 ABI remains a gap; the two-command limit at this checkpoint
was subsequently expanded as described below. The
protocol fixtures exercise the production reader and request-copy routines
under address/undefined-behavior sanitizers; they do not execute GPU work.
Generator unit tests and both kernel builds passed. Kernel builds use
`c6cf347718176e0a9da776a0b645792d9c9dce23` plus the retained DRM source.

The immutable bundle is
`/Users/alex/.local/state/vinix/omarchy-m1-abi-port-20261114/bundle/`.
Its sibling `inventory.json` has SHA-256
`374939ce981051c8f511c80e31af864c0e9de9ea7dfd495dc1dda37de3d52773`.
The retained checker supports `check-inventory BUNDLE RECEIPT`. Linked kernel
SHA-256 values are `ac2218487f5e7baab4d4a2aa7204022ef1ab7f45e809057dcba0f8485e64af9d`
(AArch64) and `4c0c5ff068f72f9ae4ef785de0ea07bd3b71acaf6397b442d07b24fd862b58c2`
(x86_64). No hardware reboot was performed.

### Workqueue event ownership

Native G13 jobs now share an event per active subqueue, matching the
reference's lazy workqueue ownership. Retirement and fault attribution use
each job's expected value, rather than the newest value on the shared slot.
Publication is ordered, the outstanding window is bounded to 127 values,
and discarding an unpublished tail rolls back both its stamp and event
sequence. The final job releases the physical slot without resetting its
firmware counters.

Prepared jobs are tracked before publication. They pin queue ownership,
survive cleanup failure, and are included in firmware-stopped teardown.
Caller-owned prepared objects remain valid for discard after shutdown;
submitted and abandoned objects are reclaimed by the manager. A separate
lifetime review found and resolved abandoned-object and publication-order
hazards. Sanitizer fixtures exercise cancellation, partial completion on a
shared stamp, quarantine retry, fault isolation and shutdown. The reference
contract check and AArch64 build passed. The x86 build excludes these GPU
modules; its preceding wire checkpoint remains applicable.

This does not close the general submission/scheduler or overlapping render
scene gaps. Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-workqueue-events-20261114/bundle/`,
built from `62039d407` plus the retained GPU source. The sibling inventory
SHA-256 is `39a3123870efd6ffd7e42256ec5d5f74b6770502fb34950c141f06300c180549`;
the linked kernel SHA-256 is
`df89f6ecae62e577ebdb368f4b9c788d55d6c52d0f7ded64fcb121f513ecf4ee`.
Use the retained checker with `check-inventory BUNDLE RECEIPT`.

### Complete TVB extension publication

TVB growth now stages all requested GPU blocks and acknowledged mappings
before changing either published table or BlockControl. A fallible pointer
table reservation and reverse cleanup preserve the committed prefix when
metadata allocation, GPU block allocation or UAT flush fails. One successful
commit publishes the complete extension. Active firmware retains ownership
of Info counters. Scene-slot lifetime and overlapping scenes remain separate
gaps.

The kernel-allocator sanitizer fixture (`-gc none`) covers both firmware ABIs,
every allocation/flush failure position, metadata exhaustion, an existing
heap's failed extension and retry, complete publication and active Info
preservation. The reference gate and unit tests passed, as did the isolated
AArch64 build from `2bfd32740` plus the retained GPU source. Generated C was
inspected for the staging allocation and every cleanup exit; a separate
lifetime review found no blocker. No GPU execution was performed.

Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-tvb-transaction-20261114/bundle/`.
The sibling inventory SHA-256 is
`6f8dd754bed0e2a6b6d22139e501e7472dc1540bcb9919bd5e1427aa2b98c4f7`;
the linked kernel SHA-256 is
`960fe9df419d8af974fc0ea3c1ac52bb23fa435d81b64db67efdc3f186d887bc`.
Use the retained checker with `check-inventory BUNDLE RECEIPT`.

### Scene-bound TVB ownership and binding

The backend now acquires a slot after complete scene allocation, shares it
across overlapping scenes, and releases it after the last scene's backing
retires. An unchanged idle token preserves its binding; displaced tokens
select the oldest free slot. Vertex publication includes InitBuffer when a
binding or heap extension requires it. Canceling the first unpublished scene
does not lose the surviving scene's required bind. GrowTVB selects only a
live, reserved scene owner matching the firmware's VM and slot.

Sanitizer fixtures cover slot exhaustion, overlap, cancellation, final release,
binding reuse/growth, oldest-free selection and stale ownership. The actual
owner selector is executed; GrowTVB ACK transport is checked separately. The
reference contract/unit checks, lifetime review and isolated ARM build passed.
The build uses `bbcd8e85a` plus the retained `g13.v` and `gpu.v`. The active
legacy userspace path still serializes submissions. Shared TPC backing is
implemented in the later change below; complete scheduler backpressure remains
a gap.

Fresh package HEAD `1438c19ff34c53704ad8cf295dedb8ae47936a59` retains kernel
pin `bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa pin
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`. The refreshed audit remains
`not_equivalent`; no hardware was accessed. Sources, audit output, tests and
kernel are retained at
`/Users/alex/.local/state/vinix/omarchy-m1-scene-ownership-20261114/bundle/`.
The sibling inventory SHA-256 is
`6185bd5331cceb589c3429697777a231f8da3c0b8836d1d59aaaa1bc75f5cc75`;
the linked kernel SHA-256 is
`ec48ec1c51dea4063b75ae89265815c82a6b7fe6a6a4eb92fea47c7425db2513`.
Use the retained checker with `check-inventory BUNDLE RECEIPT`.

### Linux DRM request transport correction

Direct comparison with the packaged `drivers/gpu/drm/drm_ioctl.c` corrected
an assumption in the first wire component: unknown ioctl input bytes are
preserved and echoed by read/write requests, rather than rejected. The
extensible path now intersects request/driver directions, sizes the complete
buffer, copies output after handler errors, gives output faults precedence,
and rejects missing handlers before allocation or user access. Nested Asahi
command payloads retain their separate unsupported-field validation. Legacy
requests keep their exact size/direction and error-output rules.

Requests up to 128 bytes use a real stack array, matching Linux DRM's fast
path; larger buffers use fallible allocation with one deferred release. The
production node ioctl is executed under sanitizers with allocator/usercopy
fault injection, live-buffer accounting, short/extended records, unknown-tail
echo, direction intersections, driver errors, nil handlers and legacy cases.
Lifetime review and both architecture builds passed. Generated C confirms
stack storage on both architectures. The x86 blob was forcibly regenerated
because its make input list excludes imported DRM sources.

Evidence, original reference C, generated C, binaries and logs are retained at
`/Users/alex/.local/state/vinix/omarchy-m1-drm-copy-20261114/bundle/`, built
from `2a2e4bc5f` plus the retained DRM source. The sibling inventory SHA-256
is `eda39f2b3bb61006bbd8542423e89da2c938f06bd1a56269db5d483109f59cf6`.
Kernel SHA-256 values are
`d16fc504733630e8d1c32a130c8e7b4c17a77cb64f5c5e9a1581053239ef9040`
(AArch64) and `727fbc459e66f0ae50d31d1b51d7101504e04a50a74f6d9316b09214901dd1de`
(x86_64). No hardware execution was performed. The modern Asahi ABI remains
unregistered; the earlier ABI/scheduler/Mesa gaps are not closed by transport.

## Validation and continuation

The host fixtures execute production page-table, publication, retirement and
recovery code with privileged services replaced. They cover both ABIs,
pending-array boundaries, fault isolation, timeout fallback, channel ACKs,
ring wrap, malformed indices and retained ownership. The source gate checks
the corresponding contracts against the pinned Asahi source. These are host
protocol checks, not GPU execution evidence.

Evidence for this continuation belongs in the fresh directory
`/Users/alex/.local/state/vinix/omarchy-m1-parity-20261114/`. The kernel source
snapshot starts at `e40d17a12a630e6e87d29f040322d1fee670e77d` plus this change.
Both kernels built successfully. The two sanitizer suites, firmware ABI and
work-command layout tests, OPP test, layout/reference unit tests and the expanded
Asahi source gate passed. Linked ARM disassembly contains page/range TLBI,
retirement and recovery paths.

The retained `parity-evidence.json` has SHA-256
`a8b532e32bee3406b065014ccd034f71b18765b67bea6eb5c5fa24618a6040bf`.
`v run tools/agx-re/check_m1_parity_evidence.v check STATE_DIR` verifies the
complete named receipt, source snapshots and artifacts; it explicitly does
not certify full parity. Kernel SHA-256 values:

- AArch64: `b318309d055de46dac51b3aaf661cd2bb245fd4b84fbe85329bd6fa28bc924e3`.
- x86_64: `aeed640beea5b93a3509de9f2dfbb7b4acbd445427d90f7e385ef5a3010b5c31`.

The configured hardware endpoint `sergey@macbook-air-sergej.local` failed DNS
resolution during the read-only SSH check. A reachable M1 and a way to boot
Vinix are needed to validate the new recovery/retirement foundation before
queue concurrency and ABI migration can be qualified.

### Event counter continuation

The event change was built separately from
`7442c64d0d78f3d1353ef4b8b6ed2d85fe48121d`, with only
`kernel/gpu/agx/event/event.v` changed in its isolated kernel worktree.
`v run tests/agx-event/run.v --sanitize` passed initialization of all 128
slots, 300 slot reuses, stale completion isolation, wrap through zero and
exactly-once fence signaling. The AArch64 kernel built successfully; its
SHA-256 is `c71cdeb14a19dcbc9ddfcc307616dc1c15dcef48ba50d2657c9ed27bc495ae46`.
The x86 kernel excludes the GPU modules and is unchanged by this continuation.

Sources, the reference `event.rs`, the kernel delta, native executable, ELF
and build/test logs are retained at
`/Users/alex/.local/state/vinix/omarchy-m1-event-20261114/bundle/`.
The sibling `inventory.json` pins the complete bundle and has SHA-256
`0e151a6fc637d12e4f7f806b1d82057b4f2f1af7a1ec62114b38e8d29fad2022`.
Verify with `v run tests/ios/evidence-delta-archive.v check-inventory BUNDLE RECEIPT`.
This integrity receipt does not certify native GPU execution or full parity.

### TVB feedback continuation

The feedback policy was built from
`a151aabf30fbbc4a5457bb23bfa06ba7adaa5452` with only
`kernel/gpu/agx/gpu/g13.v` changed in a fresh isolated kernel worktree.
The production-policy sanitizer fixture, reference unit tests and expanded
Asahi source gate passed. The AArch64 kernel built successfully; its SHA-256
is `7a511c8b5762bc6f31b49956cfe8d1c8f75e8a919cc70b5ea56163bb9e7488ba`.
The x86 kernel excludes this GPU module and is unchanged.

The complete named bundle, including sources, reference policy, kernel delta,
native executable, ELF and build/test logs, is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-tvb-20261114/bundle/`.
The sibling `inventory.json` has SHA-256
`c3101eb209261bc2af516be1b9ce97b5f0f7e8b1da6f795c0d90a80cb15c5541`.
Its retained `evidence-checker.v` verifies it with
`v run BUNDLE/evidence-checker.v check-inventory BUNDLE RECEIPT`.
Allocation itself is replaced by a recorded request in the feedback fixture;
this validates the policy, not hardware memory consumption. A repeated SSH
check still failed to resolve the configured M1 hostname.

### Shared tail-pointer backing and deferred file cleanup

The native render buffer now caches UAT-page-aligned tail-pointer backing.
Scenes retain references to it; growth replaces the cached reference after
successful allocation while older scenes keep their original backing. Only
the last owner invalidates and releases a buffer. Failed invalidation marks
it retiring so later scenes cannot reuse a partially unmapped allocation.
Repeated same-size scenes require no new TPC metadata or backing allocation.

Lifetime review also exposed unsafe file teardown after failed queue release.
Closing files now retain their complete VM/object graph until all queue
resources retire. An intrusive list retries cleanup after job completions and
firmware stop. Registration holds the manager lock to prevent enqueueing after
the worker's final poll. Quarantine prevents new preparation/submission while
allowing idempotent teardown retries. Callbacks run outside the manager lock.

ASan/UBSan fixtures execute the production helpers and check 500 cache reuses,
growth with live older scenes, allocation/invalidation failure, final release,
partial queue cleanup, bounded multi-file retries and the shutdown-registration
race. Reference gates, their unit tests, lifetime review and an isolated ARM
kernel build passed. The build uses `f7607385b` plus the six retained kernel
files; source hashes were compared with that worktree before sealing.
The refreshed audit remains `not_equivalent`; no hardware was accessed.

Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-tpc-20261114/bundle/`.
The sibling inventory SHA-256 is
`af0c7e783a3e4266921555b38a6c47d4293136f8c203ccc62c2f75c0c2832751`;
the linked kernel SHA-256 is
`94ec13891e6cc95edb907ead7f2f4565911a125c5f02bc2f0e64f5413541c629`.
Use the retained checker with `check-inventory BUNDLE RECEIPT`.

### Initial TVB allocation and compute priority defaults

The native queue now allocates the reference's default eight TVB blocks
before its first scene. The existing staged allocator publishes the complete
table and inactive firmware counters; initialization failure unwinds the
whole unpublished graph. G13 compute queues now take priority fields 0 and 5
from the highest-priority entry when using the reference's default disabled
compute preemption. The other priority fields retain the requested band.

ASan/UBSan checks cover every initial shared-buffer, UAT-table/block, metadata
and flush failure on both firmware ABIs, as well as all twelve band/pipe
combinations and their encoded priority bytes. Reference gates, their unit
tests, lifetime review and an isolated ARM kernel build passed. The build
uses `df24c48dd` plus retained `gpu/g13.v` and `fw/workqueue.v`, verified byte
exact before sealing. The audit remains `not_equivalent` and no hardware
was accessed. Module/debug overrides and full scheduling remain unchecked.

Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-queue-defaults-20261114/bundle/`.
The sibling inventory SHA-256 is
`b7fced80d8483d7c259bab00f9e656284e07fd6a936a253bccf9f6dc274d7ff3`;
the linked kernel SHA-256 is
`69498515b1729c638913630c6a78ae00b51f29f1ac189ec1e4cb45aea2908166`.
Use the retained checker with `check-inventory BUNDLE RECEIPT`.

### Firmware queue identity, command counters and framebuffer defaults

Firmware identities now come from a device-wide 64-bit sequence starting at
two, matching Asahi's reserved system IDs. File-local queue handles remain
independent. Notifiers, workqueue UUIDs, start-operation generations and the
three command client-sequence bytes use the reference's 32/8-bit projections.
Previously, two clients could publish the same file-local ID as their firmware
identity.

Firmware 13.5 also uses one command counter per queue across all subqueues:
compute reserves one value; render reserves fragment then vertex values.
The counter now reaches both command headers and their microsequence start
operations instead of repeatedly emitting the first job's 0/1 values. Failed
construction may consume values; cancellation does not rewind the sequence.
Both expanded auxiliary-framebuffer records now set their reference tail
value to `0x100000` while preserving dimensions.

ASan/UBSan tests cover mixed work, independent queues, canceled gaps, 64-bit
wrap, command/start agreement, encoded framebuffer tails and byte-exact legacy
start operations. Reference gates, their unit tests and the isolated ARM build
passed. The build uses `91f65a71f` plus five retained kernel files, compared
byte-for-byte before sealing. These value fields add no allocation or lifetime.
Full ABI/scheduling/VM/Mesa migration and the remaining firmware comparison
are still incomplete; the audit remains `not_equivalent`. No GPU was accessed.

Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-command-counters-20261114/bundle/`.
The sibling inventory SHA-256 is
`efc088248679501ce00869a38585a746169ee32a12ba440829b5f07fed001d6e`;
the linked kernel SHA-256 is
`3400890dd542e690b63a9654513714f62de6ea1e64401c30ceb849e92b7b5203`.
Use the retained checker with `check-inventory BUNDLE RECEIPT`.

### Final package freshness check

The final remote check found package HEAD
`aeb60b5e8dbf2974b8a8a8da6893030eb25b2c19`. A fresh clone's kernel and Mesa
PKGBUILDs are byte-identical to `1438c19f`; the pinned driver and userspace
revisions above remain current. Omarchy HEAD remains `663aff7b`. A fresh audit
of Vinix `49c3af756bab2bba31d47a8ec3b4c35abfbc844d` against these references
passes the selected gates and retains the `not_equivalent` verdict.

Its complete source/audit bundle is
`/Users/alex/.local/state/vinix/omarchy-m1-command-counters-20261114/freshness-audit/`.
The sibling `freshness-inventory.json` SHA-256 is
`3ec287c00de04872522bb7385a1bac41b1eec523806bb1fa03d6672fb5d6d532`.
The original sealed feature bundles and receipts were preserved.

### Asynchronous native submission polling

The native G13 ioctl now snapshots and validates user input, prepares jobs and
installs output fences before returning. Input dependencies, queue backpressure
and compute-to-render completion are polled by the GPU worker. An unsignaled
dependency blocks its own queue while unrelated queues progress. Failed
dependencies retain their errno on the output fence; failed compute cancels
the unsubmitted render half. At this checkpoint the active ABI accepted only
the legacy single-command or compute-then-render pair; the later mixed-batch
change below removes that restriction on the native path.

An allocation-free poll loop maintains per-queue FIFO. Older retained nodes
are prepended ahead of concurrent enqueues. Manager-locked registration closes
the final-shutdown-poll race. Pending nodes own caller-prepared job pointers
until publication, and keep an additional file/VM pin through every callback
gap. Internal callback counts and compute completion flags govern retirement;
client-signaled output fences cannot advance phases or release node backing.

ASan/UBSan fixtures execute the production ioctl, staging, sync objects,
callbacks, poller, registration and dispatch guard with injected GPU services.
They cover dependencies/errors, independent queues/FIFO, result references,
backpressure, setup failures, concurrent enqueue, stopped registration and
shutdown with published/prepared jobs. Two hundred immediate-retirement cycles
leave no pending-node allocation, job record or file/VM pin in the fixture.
Existing retained sync-object/fence allocations remain outside that measure.
The cleanup/recovery fixtures, source/unit checks, two independent lifetime
reviews and an isolated ARM build passed. Generated C confirms fixed stack
storage in the poll loop; native execution remains untested.

Package HEAD `fb18a8a7359142ab33f65d906d956b3cc3590a53` retains the same
kernel and Mesa pins. The source audit remains `not_equivalent`; the modern
ABI, general batches, firmware barriers, VM/GEM and other rows above remain
incomplete. The build uses `1c078554a89bbfbd5b3eeeaaac4213a8396ab584` plus
the five retained kernel files, verified byte exact before sealing.

Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-async-20261115/bundle/`.
The sibling inventory SHA-256 is
`18ac9e8176c0d12c3c182acd5117555b474f8273faf9e004015f41107dd1a170`;
the linked kernel SHA-256 is
`7a768ea652765d50ed3bf17dbce5e5a1bfa8748894525533239a201162890866`.
Use the retained checker with `check-inventory BUNDLE RECEIPT`.
No hardware access, boot or reboot was performed.

### Native mixed command batches

Native submission now accepts up to 64 render/compute commands in arbitrary
order, matching the packaged reference's hardware-command count limit. The
legacy descriptors and payloads are staged before GPU preparation, and barrier
indices are checked against previous commands of each subqueue. At this
checkpoint execution remained serial within a queue. The later overlap change
below relaxes that restriction within a batch; firmware barriers remain separate.
The fake backend retains its existing two-command contract.

Staged payloads use fallible temporary heap storage. The pending node owns
prepared jobs, indexed callbacks and one aggregate fence. Reverse cancellation
refunds unpublished event reservations from newest to oldest. Fence notification
follows all callbacks and result-reference releases, with the extra file/VM pin
still held. Partial output-installation failure signals its exposed sync prefix
after cleanup and after releasing the file lock.

ASan/UBSan fixtures pass four full-batch orderings; every one of the 64
preparation, callback and stop-during-registration failure positions; both raw
allocation failures; invalid descriptors/barriers; middle-command faults;
shutdown; aggregate-fence observers; and the fake pair limit. The existing 200
immediate-retirement cycles still drain pending nodes, jobs and file/VM pins.
Existing retained sync-object/fence allocations are outside that measurement.
The TPC fixture also passes 64 simultaneous shared scene references. Cleanup,
recovery, source gates, unit tests, independent lifetime review and an isolated
ARM kernel build pass. The local ioctl stack frame is 7,088 bytes in the retained
disassembly; this is not a peak call-chain measurement.

The build uses `b06a335c04f183a3aee13bd3d312cd88d102d1fb` plus four retained
kernel files, compared byte-for-byte before sealing. Package HEAD remains
`fb18a8a7359142ab33f65d906d956b3cc3590a53`, with unchanged kernel/Mesa pins.
The audit remains `not_equivalent`: modern ABI registration, firmware barriers,
same-queue overlap, VM/GEM/Mesa integration and the other differences above
remain incomplete. No hardware access, boot or reboot was performed.

Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-batches-20261115/bundle/`.
The sibling inventory SHA-256 is
`118504e4b838f9a9d2a8f8d93acbeb02e08e4f73ac148314365dc81e4e9cdeee`;
the linked kernel SHA-256 is
`61784c84cf87d8a8453e8dd0b2cb3a1b880e0988e3d18580ee590c35afa246aa`.
The retained checker passes `check-inventory BUNDLE RECEIPT`.

### Overlapping commands within a native batch

Independent commands in one submission can now publish together, instead of
waiting for every earlier command's callback. Barrier indices resolve to scalar
positions in the pending node before staged storage is freed. A barrier waits
for the specified command of its own subqueue; render completion includes both
vertex and fragment work. A blocked dependency or full ring holds later commands
on that pipe while the other pipe can progress. Later submissions on the same
queue retain FIFO through retirement.

Submitted jobs no longer block publication by themselves. Both native submit
methods check quarantine while holding the manager lock, closing the gap between
polling and publication. Completed errors are checked before further work, and
the aggregate fence still waits for all callback references. A synchronous final
callback's error is read after observing the callback count reach zero. Existing
per-job/per-scene backing, shared TPC/TVB owners, event tickets and reverse
cancellation retain their ownership rules; the poller adds no allocation.

ASan/UBSan checks pass both independent completion orders, older barrier targets,
subqueue FIFO, per-pipe backpressure, quarantine at publication, a fault with
another published job still pending, four full 64-command reverse-callback
batches, shutdown and synchronous first/last errors. The production reaper
fixture also retires 64 compute jobs and 64 paired render jobs; vertex-only
completion retains all render scenes. Existing batch, close and recovery
fixtures, source gates, unit tests and independent lifetime review pass.
The existing 200 immediate-retirement cycles still drain nodes, jobs and file/VM
pins; retained sync-object/fence allocations remain outside that measurement.

Isolated AArch64 and clean x86_64 kernel builds pass from
`cab44e91988c37aae1bab7af0fe7183dcd5ddd8a` plus three retained kernel files,
compared byte-for-byte before retention. Generated ARM C uses fixed arrays in
dependency resolution and polling. The local ioctl frame is 7,600 bytes in
disassembly; this is not a peak call-chain measurement. The ARM ELF and C were
retained before switching architectures; initial sparse-dependency and mixed
object failures are preserved separately from the successful clean x86 build.

A fresh Omarchy clone is at `c30411b92bd3bf87535bef4e13ce7015087fc648`.
Package HEAD remains `fb18a8a7359142ab33f65d906d956b3cc3590a53`, retaining
the kernel and Mesa pins above. The source audit remains `not_equivalent`.
Firmware barrier commands, overlap across submissions, modern ABI registration,
VM/GEM/Mesa integration and the other listed gaps remain incomplete. No hardware
access, boot or reboot was performed.

Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-overlap-20261115/bundle/`.
The sibling inventory SHA-256 is
`f7ce46536c4017b717a4c976fd26f9f526ae8e6e0b4f93e6378ff594cf367930`.
Linked kernel SHA-256 values are
`a0d2ba244097b05b72b6f7df692c32cf4996a5730c9b53ee2d9264a45dd8130f`
(AArch64) and
`1bf2f083e14a9849213d607177e02b1bcd7e5280084f5e310da0abde13cd2a70`
(x86_64). The retained checker passes `check-inventory BUNDLE RECEIPT`.

### Firmware barrier prefixes and physical event ownership

Nonzero in-batch dependencies now produce the packaged reference's explicit
barrier records, with UUID `0xffffbbbb`, external field zero and internal type one.
The two type fields occupy distinct words at offsets `0x1c` and `0x20`; the
record remains 64 bytes. Prefixes precede InitBuffer/Vertex or RunCompute in
one publication transaction, including ring capacity and retirement accounting.

Each consumer pins the physical event counters it references until its complete
graph passes invalidation or firmware stops. Producer retirement, partial setup,
flush failure and quarantine do not release those pins early. Records occupy
reserved tails in existing private microsequence/InitBuffer allocations; the
current ABI forms still fit their existing 16KiB pages. Logical microsequence
lengths remain unchanged. Setup runs after all jobs are prepared and before
callback/fence installation.

Generated-C inspection caught hidden temporary allocations in the prefix array
and firmware notification copies. Fixed three-entry storage and direct packed
ring writes remove them. A maintained checker and its negative selftests verify
five generated helper bodies. This does not measure whole-kernel allocation
rates or qualify native GPU execution.

ASan/UBSan checks pass the independent byte oracle, tail canaries, 400 producer/
consumer lifecycle cycles returning all 128 event slots, 1,000 physical ownership/
reuse cycles, every barrier-setup/stop position in a 64-command batch, wrapped/
full rings, retry and conditional TVB binding. Existing async, close, recovery,
lifetime, source and unit checks pass. Independent lifetime review approved the
pins, fixed storage and notification ordering. An isolated AArch64 build and
ordinary x86_64 build pass from `0be4a7d02ba11ef73e2007d35079dff24b02f5a3`
plus six retained kernel files. Every AGX V source matches the final ARM build
input byte-for-byte.

The fresh Omarchy clone is `6306130eb877be9312197b4ea74eb0d0dc626f0d`;
package, kernel and Mesa pins remain unchanged. The audit remains
`not_equivalent`. CPU callback waits, index-zero ordering through batch FIFO,
modern ABI integration, full firmware-driven/cross-submission scheduling and
VM/GEM/Mesa integration remain incomplete. No native GPU test, Vinix boot or
reboot was performed.

The complete retained bundle is
`/Users/alex/.local/state/vinix/omarchy-m1-barriers-20261115/bundle/`.
Its sibling `inventory.json` SHA-256 is
`8e6967c99a6a654b1a56e4e4b56a7506b2247e77b2dd8aa0b54785f3cda5e1be`.
The sibling `bundle.tar.gz` contains the bundle and receipt; its SHA-256 is
`7489c179c96f59d148629ca9487624050cf076fe5bcb86e3025c8cfb62644949`.
Both the original and a full archive extraction pass the retained
`check-inventory BUNDLE RECEIPT` checker. Linked kernel SHA-256 values are
`f17318ba7d2e45474fd9ac3cede06b4ed439d43523b525229fe1d2819da6ed15`
(AArch64) and
`914068b75c957ef1e496c11a6d8edef8619bbcabfd6d568269e2f77e334e8376`
(x86_64). Storage interruptions were resolved with a task-owned RAM build;
the accepted artifacts and archive are retained on persistent storage.

### Firmware-driven dependencies within a submission

Nonzero in-batch dependencies now wait for producer publication, then use the
installed firmware prefixes to order execution. The worker no longer waits for
producer CPU callbacks. An unpublished producer still blocks its dependent
subqueue, and errors cancel only jobs that remain caller-owned. Published
consumers retain their backing and physical event pins until actual completion
stamps or firmware stop. Aggregate fences still wait for all internal callbacks
and result references.

Independent lifetime review found two shutdown races: callbacks could reach zero
while the node retained unpublished metadata, either during publication or just
before its final callback-count load. Both failures were reproduced. The poller
now checks stop during publication and checks it again **after acquiring zero
callbacks**, then releases remaining prepared pointers before retiring the node.
The final review approved the ownership and ARM acquire/release ordering.

ASan/UBSan validation passes four 64-command dependency chains published before
any callback, separately injected firmware execution, reverse callback delivery,
fragment/older targets, and failed producers retaining published consumers.
Shutdown passes 512 before/after-publication cases plus 16 final-count-load cases.
The real barrier/reaper fixture passes 480 ownership cycles, including 80 with
consumer callbacks before producer callbacks; every cycle returns all 128 slots.
Event, close, recovery, publisher, source-gate and three V unit suites also pass.
The injected firmware model does not establish native firmware recovery behavior.

Isolated AArch64 and ordinary x86_64 builds pass from
`90c3e83bcca5b8f7e06322ce9ac0fd9d361a908b` plus the retained `pending.v`.
Every AGX V source matches the isolated build input. The generated-C checker still
passes its five prefix helper bodies; this does not measure whole-kernel leaks.
An initial build was interrupted by incoming continuation; the final revised ARM
input was rebuilt successfully. No native GPU test, Vinix boot or reboot occurred.

Fresh Omarchy `b80cf8e097078682a520c264e0f1d307eadb8c13` and package checkout
`54c38bc854bc6603829a44e03a6bc7fabd9ccb7b` retain the same kernel and Mesa pins.
All selected source gates pass, while the audit remains `not_equivalent`.
Index-zero dependencies still use batch FIFO. Cross-submission overlap, modern
ABI registration, VM/GEM/Mesa migration and the other gaps above remain open.

The complete evidence bundle is
`/Users/alex/.local/state/vinix/omarchy-m1-fw-scheduling-20261115/bundle/`.
Its sibling `inventory.json` SHA-256 is
`dba322c8e43604e7b3a4f109e666d81f772b73510435b9c2417d9ac9fddc9053`;
the unchanged retained `check-inventory BUNDLE RECEIPT` checker passes.
Linked kernel SHA-256 values are
`5fe75e0f4c6679caf07fc2362f58e0be36f06bda0e4a2d20db4c05341b3f3039`
(AArch64) and
`d65a0e2c4308b0c0415381900ac04dcf7deed9c3e5785ec090d976e6006a1a83`
(x86_64). The sibling `bundle.tar.gz` contains the full bundle and receipt;
its SHA-256 is
`ad63ac868fff98baf7e554dbba95ab4215257c29e320206f8e821122612898e5`.
A complete archive extraction and the canonical bundle both pass the unchanged
inventory checker. Only the task's rebuildable checkout was removed after the
complete retained bundle passed verification.

### Pipelining independent submissions

Later independent batches on one queue now enter firmware once older publication
finishes, allowing either pipe's later batch to complete first, as the packaged
Asahi scheduler permits. Pending nodes retain separate callbacks, VM pins and
aggregate fences. The worker keeps only queue identities and unpublished-work
bits in fixed stack arrays; no reference to an older node survives a poll.
Partial publication and unsatisfied input syncs still hold later same-queue work.

Explicit index-zero bits are staged separately from in-batch dependency positions.
If either bit is present, the whole batch conservatively waits for **all** prior
same-queue retirement. This preserves ordering without trusting a client-signaled
user fence, but remains more restrictive than upstream's captured initial events.
Full firmware initial-event capture and scheduler admission/backpressure remain
open, alongside modern ABI/VM/GEM/Mesa migration and the other listed gaps.

ASan/UBSan checks pass reverse cross-batch completion with independent node/result/
VM ownership, overlapping 64+63 jobs, both initial-dependency bits, partial
publication, a concurrent append, a full 128-entry queue table with overflow and
resumption, failed-input isolation and 12 new multi-batch shutdown interleavings.
The prior 528 shutdown cases also pass. Production reapers and event management
pass 64 and 127 live compute/paired-render jobs with reverse traversal; vertex-only
completion retains every render scene. Close, source gates and three V unit
suites pass. Independent lifetime review approved the final implementation.

The generated-C checker now covers eight barrier/publisher/scheduler helpers,
rejects hidden temporary allocations in each, and requires both fixed 128-entry
scheduler arrays. Its negative selftests pass. This is not a whole-kernel leak
measurement or evidence that native firmware executes the injected host model.
No GPU access, Vinix boot, reboot or deployment was performed.

Isolated AArch64 and ordinary x86_64 builds pass from
`c89fc75e1eafba8f6fe3274c5a5ab99b02edd702` plus the retained `pending.v`.
Every AGX V input matches the isolated checkout. Fresh Omarchy
`d7cbcac2f96a579123e285fb223eab0c1e80dc20` and package checkout
`dd29deefca1f82a325ec82513e5ed25a094a7f13` keep the same kernel and Mesa pins.
All selected audit gates pass; the whole-driver verdict remains `not_equivalent`.

The complete retained bundle is
`/Users/alex/.local/state/vinix/omarchy-m1-pipelining-20261115/bundle/`.
Its sibling `inventory.json` SHA-256 is
`0dcdf95d42cb3b622632d68d483d137be46f86b607db9f21418b4fc38d2f869e`.
The sibling `bundle.tar.gz` SHA-256 is
`3b9753cb0d2d833feb839afef96201b7fef0ce9198881c1cddf4c6fdaec59d3c`.
The canonical bundle and a complete archive extraction pass the unchanged
inventory checker. Linked kernel SHA-256 values are
`ba0d6473b410a6558c483896fcf4394bb88ad08e5b88ceb5557add4fdd1362cf`
(AArch64) and
`25942c343bcf819d49ca9e15e01a4a9bee26b6da61dac2cdc1ed4dbcea889a3f`
(x86_64).

### Captured initial firmware events

Explicit index-zero dependencies now capture the prior accepted event on each
requested subqueue before preparing the new submission. Individual commands use
firmware prefixes instead of waiting for whole-batch CPU retirement. Acceptance
validates every prepared job, including both render tickets, before atomically
updating the queue's weak markers and enqueueing. Rejected ioctls preserve the
previous accepted state.

Captures pin physical stamp slots while prefixes acquire their own pins. A
monotonic host reservation identity excludes future reuse of a canceled firmware
value/sequence. Publication waits for older unpublished reservations, falls back
to older published work after cancellation, and omits absent sources. Immutable
wait metadata permits flush retry and two-to-one record compaction while retaining
both pins until complete graph invalidation or stopped cleanup. Cancellation on
input-fence errors remains a Vinix adaptation; complete upstream input-error
policy is not certified by this change.

Native generated-C inspection caught an addressed loop-local `memdup` and V
structural comparisons of queue pointers. Passing the source by value and using
explicit `voidptr` identity remove those defects. The ARM acceptance frame fell
from 27,264 to 288 bytes. Kernel stacks are 64 KiB; this does not establish that
the old frame overflowed. The checker now guards 19 generated function bodies
against temporary allocations and structural copies, requires fixed stack
arrays, passes negative selftests, and rejects the retained defective C. These
checks do not measure whole-kernel leaks.

ASan/UBSan validation passes 1,000 initial-event cancellation/ABA/rollover cycles
and wrapped zero targets; 140 production acceptance/capture/resolution/reaper
lifecycles; byte-exact cancellation fallback; two-source compaction, flush retry,
quarantine, partial pin overflow, foreign equal queues and manager-reset cleanup.
All 128 physical slots return after cleanup. Async checks cover per-command and
immutable cross-submission targets, execution before producer callbacks, rejected
admission and setup/stop cleanup. Existing overlap, 540 shutdown interleavings,
64/127 live-job reapers, publisher/recovery, close, source gates and three V unit
suites also pass. Independent review approved the final new lifetimes.

Isolated AArch64 and ordinary x86_64 builds pass from
`3c8c576fb62aad653336f063d2afbcc245c8c7d3` plus seven retained AGX files.
Every AGX V source matches the isolated checkout; all seven changed sources match
both retained input snapshots. The ordinary x86 build excludes native AGX code.
Fresh Omarchy `4f26515d55f5d03ddf884a8b416f3b66b8ee7ae4` and packages
`dd29deefca1f82a325ec82513e5ed25a094a7f13` retain the same Asahi/Mesa pins.
All selected audit gates pass; the whole-driver verdict remains
`not_equivalent`. Modern ABI/VM/GEM/Mesa integration, full admission/backpressure,
input-error policy, remaining render defaults, topology and power management are
still open. No native GPU execution, Vinix boot, reboot or deployment occurred.

The complete evidence bundle is
`/Users/alex/.local/state/vinix/omarchy-m1-initial-20261115/bundle/`.
Its sibling `inventory.json` SHA-256 is
`c0e368ae7f59a82763f5d136f65c7fbaf158658ea25cab54a87440c39d8e1076`.
The sibling `bundle.tar.gz` SHA-256 is
`6168beafcf4af7b90190ec9bbb7209e165a5189066e0caffb0327fca00ecddc4`.
Both canonical and fully extracted bundles pass the unchanged inventory checker.
Linked kernel SHA-256 values are
`690028b9dd5e5d6f81319a5e357506fd61805f383afe2e85e5d958f859e2fca6`
(AArch64) and
`baa14451cf5b65b7791bb96903c93ba78e18f4ad58acf0e0c53fdf7769914b8a`
(x86_64). Rejected intermediate binaries/C are explicitly labeled diagnostics.

### Input-fence error handling

The pinned Asahi scheduler adds input fences as ordering dependencies.
`drm_sched_entity_add_dependency_cb` releases signaled waits without copying
their errno into the dependent job; `drm_sched_run_job_work` reports that job's
own completion error. Vinix previously canceled the waiting submission on an
input error. Its native pending worker now waits for every original input fence
to signal and leaves the input errno separate from the submission's GPU result.
Firmware initial-event waits, producer-fault handling and shutdown ownership
remain enforced.

Eight ASan/UBSan ioctl scenarios permute two input/signal orders and successful
versus faulted GPU completion. They verify that neither an errored input nor a
replacement syncobj fence releases an unsignaled original snapshot. Existing
mixed-job, cross-submission, initial-prefix, own-fault, backpressure, 64+63 overlap
and 540 shutdown cases pass. Three V unit suites pass, including negative policy
gates and a scheduler-C retention check. The source audit now retains and hashes
the actual scheduler C files and Rust wrapper. All selected gates pass; the
whole-driver verdict remains `not_equivalent`.

Isolated AArch64 and ordinary x86_64 builds pass from
`c8c44aaa2c6c5b8426ece91b5b77f2f8663a09bc` plus the retained `pending.v`.
Every AGX V source matches the isolated checkout; `pending.v` matches both
retained build snapshots. Twenty generated ARM helper bodies and checker
selftests pass the allocation, structural-copy and fixed-storage guards. The
ordinary x86 build excludes native AGX code. No ownership fields or new frees
were introduced. The preceding lifetime/event/publisher/close evidence remains
unchanged. No native GPU test, Vinix boot, reboot or deployment occurred.

References reuse the immediately preceding fresh Omarchy clone
`4f26515d55f5d03ddf884a8b416f3b66b8ee7ae4` and package/kernel/Mesa pins.
Scheduler fence elision, complete admission/backpressure, modern ABI/VM/GEM/Mesa
and the remaining areas above are still incomplete.

The complete evidence bundle is
`/Users/alex/.local/state/vinix/omarchy-m1-input-sync-20261115/bundle/`.
Its sibling `inventory.json` SHA-256 is
`533f1e4f7f730ab4a797873dd510029bbcc6e14a0f5a291c441940164bc58d45`.
The sibling `bundle.tar.gz` SHA-256 is
`22726a81661b9ed1d123f11d0e9164220f3bc84ddeb4bf2b1c12b0b72c7dea4f`.
Canonical and fully extracted bundles pass the unchanged inventory checker.
Linked kernel SHA-256 values are
`a5b0bc70299001293f19ed684721acbc4512db44b19cb72984c0eef15cfc0707`
(AArch64) and
`a7f97f10ebb8feb9b9c5189d25d6682b0a1e3d478088cc63910fc5cd21460910`
(x86_64).

### Per-queue scheduler fence elision

The packaged Asahi driver creates one DRM scheduler and entity per user queue.
Its dependency callback ignores that entity's own completion fences. Vinix now
does the same for native queue fences without signaling them early or changing
their independent callback/result/VM ownership. External fences and fences from
other queues still wait for actual signaling; publication FIFO and explicit
firmware prefixes still order the queue's commands.

Each physical queue receives a globally serialized, non-reused 64-bit context.
Its output fences retain only an immutable private scalar, separate from public
context/sequence fields. Failed queue construction consumes the identity, and
exhaustion remains permanent rather than wrapping. Reusing a public queue handle
or releasing/resetting its resources cannot transfer provenance to a new queue.
No new queue pointer or freeing path is retained in a fence. Independent read-only
review approved identity lifetime, lock ordering and cleanup.

ASan/UBSan checks pass own/foreign queue waits, mixed own/external inputs in both
orders, reverse retirement and independent errors, shutdown, older partial
publication, initial firmware waits, generic fences with matching public fields,
and recreated handles. The production allocator passes its final two identities
and repeated exhaustion. The expanded fixture retires the earlier drained handle
namespace through production `destroy_owner`; it preserves the 1,024-object limit
and retained allocations. Existing overlap, 540 shutdown cases, immediate
retirement and close checks pass. Three V unit suites, negative identity/policy
gates, and 21 generated ARM helper checks/selftests pass. Firmware execution and
host locking remain injected; these checks do not measure whole-kernel leaks.

Isolated AArch64 and ordinary x86_64 builds pass from
`e3a5d07f4d55db18b244d344f3cf068713dea694` plus five retained AGX/syncobj
files. Every AGX and syncobj V source matches the isolated checkout, and the five
changed sources match both retained input snapshots. Ordinary x86 includes
syncobj but excludes native AGX code. Omarchy HEAD remains
`4f26515d55f5d03ddf884a8b416f3b66b8ee7ae4`; a fresh package clone is
`703430e884c0c46bce2a83f11c34a44af3f2ec5b`, retaining the same Asahi/Mesa
pins. All selected audit gates pass; the verdict remains `not_equivalent`.
Full admission/backpressure, modern ABI/VM/GEM/Mesa and the other listed areas
remain incomplete. No native GPU test, Vinix boot, reboot or deployment occurred.

The complete evidence bundle is
`/Users/alex/.local/state/vinix/omarchy-m1-queue-fences-20261115/bundle/`.
Its sibling `inventory.json` SHA-256 is
`cdf8e901a96e236ac249d86d68f649baf7f03f35daa1bab211c80d2ba85307ed`.
The sibling `bundle.tar.gz` SHA-256 is
`405811267fe7d1d1e147188b5de971f66852245d92e2a562b6f1c187ad7d829c`.
Canonical and fully extracted bundles pass the unchanged inventory checker.
Linked kernel SHA-256 values are
`4429be593a093ed7ed5b309076f16fd17f498617db9805d6b0968baec891dda9`
(AArch64) and
`6576e8aee7c66353533e4a4f0f57a90e7fe876f19e2a000d4e2813de01901a24`
(x86_64).

### Host-retirement ring admission

Compute and paired render publication now gate on the host's unretired command
positions as well as the firmware ring pointers. The pinned Asahi reference
defines free space as `size - pending.len() - 1` and requires it to be strictly
greater than the complete command count. Vinix applies the equivalent strict
predicate to `command_sequence - retired_sequence`, including every prefix and
optional InitBuffer. Both render halves validate before either ring is changed.
Corrupt or overflowing logical counters stop publication instead of wrapping.

The existing monotonic retirement high-water mark permits reverse reaping
without moving a released prefix backward. Manager locking and queue quarantine
continue to prevent reuse during incomplete cleanup. This adds no fields,
pointers, allocations or frees. Independent ownership/admission review approved
the spare-entry arithmetic and reaper interactions.

ASan/UBSan tests pass 5,120 capacity boundaries and drive the real compute/render
publishers with GPU consumption advanced but host retirement withheld. Exact
remaining capacity is refused; one host retirement permits atomic retry.
Wrapped zero/one/two-prefix commands pass with and without TVB binding. Existing
publisher/recovery tests, async regressions including 540 shutdown cases, three
V unit suites, source gates and 22 generated ARM helper checks/selftests pass.
The async fixture still injects publication services; native ring admission is
exercised by the separate production-publisher fixture.

Isolated AArch64 and ordinary x86_64 builds pass from
`fbcb0482f46fa4d2a37dd01d17b0191e952b2eca` plus the retained `g13.v`.
All AGX/syncobj V inputs match the isolated checkout; `g13.v` matches both
retained input snapshots. Ordinary x86 excludes native AGX code. Omarchy
`4f26515d55f5d03ddf884a8b416f3b66b8ee7ae4` and package HEAD
`703430e884c0c46bce2a83f11c34a44af3f2ec5b` were reverified and keep the same
Asahi/Mesa pins. All selected audit gates pass; the verdict is `not_equivalent`.

Event-slot admission remains separate: Asahi also requires
`free_slots() > event_count`; Vinix's 127-ticket preparation limit does not
establish equivalent publication or backlog behavior. Event-window predicates,
queued backlog, whole-batch readiness/credits, modern ABI/VM/GEM/Mesa and the
other listed areas remain open. No native GPU execution, Vinix boot, reboot or
deployment occurred.

The complete evidence bundle is
`/Users/alex/.local/state/vinix/omarchy-m1-ring-admission-20261115/bundle/`.
Its sibling `inventory.json` SHA-256 is
`657cc34b164dfd6ec578c3b152f032f5b7416cbd9e1779595f1bce86af99be4c`.
The sibling `bundle.tar.gz` SHA-256 is
`f929ec391baca9f495ef330607d9ee37c5506a0598d3065e874beddf55178906`.
Canonical and fully extracted bundles pass the unchanged inventory checker.
Linked kernel SHA-256 values are
`087cccb698a62cd430f29f7a3ba24a07e815ddc855e156e4cf036320eb556172`
(AArch64) and
`d82a101cc1c096cfe4999e2de3f366de304aeb406d9e46edfe7bc4f8db6ac2ee`
(x86_64).

Only byte/mode-identical root staging ELF/C duplicates from earlier completed
runs were retired when storage was tight. Every complete canonical bundle,
original receipt and archive remains unchanged; the affected state directories
retain `redundant-staging-retirement.txt` ledgers. The older artifact incident
below is unchanged.

### Event publication window

Native workqueue events now separate the last successfully published stamp from
the host-retired stamp. Asahi's `MAX_JOB_SLOTS=127` and strict
`free_slots() > event_count` admit one event only when the existing signed
stamp delta is below 126. Vinix applies that predicate independently of its
127-ticket preparation table. Raw GPU progress and unpublished cancellation
cannot grant host completion credit. Submitted retirement advances monotonically
across zero/sign wrap, so reverse cleanup cannot reduce available capacity.

Admission uses the last published stamp rather than the candidate reservation.
That distinction lets the first real job run after all 126 preceding
reservations are canceled; the published gap then holds further work until
host retirement. First ownership initializes both counters from the observed
physical stamp. No reference, allocation or freeing path is added. Independent
review approved cancellation, wrap, invalidation and quarantine behavior.

ASan/UBSan tests pass 1,000 full-window cycles, including actual crossings of
`0x7fffffff` and zero, tail rollback/ABA, cancellation holes, raw-progress
refusal and host-retirement retry. Production compute/render reapers retain
127-job coverage: 126 publish, the last stays prepared, the first host retirement
opens capacity, and the remaining jobs retire in reverse. Vertex-only completion
still retains every incomplete render scene. Existing initial-event/barrier/TPC
lifecycles, async regressions, three V unit suites and source gates pass. The
generated-C checker now guards 26 helpers, including event retain, release,
readiness and successful publication; its negative selftests pass.

Isolated AArch64 and explicitly clean-qualified ordinary x86_64 builds pass from
`c603ad27a10141461ad313363441834297924a08` plus retained event `workqueue.v`.
All AGX/syncobj V inputs match the isolated checkout and the changed source
matches both retained build snapshots. Ordinary x86 excludes native AGX.
Reverified Omarchy `4f26515d55f5d03ddf884a8b416f3b66b8ee7ae4` and packages
`703430e884c0c46bce2a83f11c34a44af3f2ec5b` keep the same Asahi/Mesa pins.
All selected audit gates pass; the verdict remains `not_equivalent`.

The preparation backlog is still bounded at 127 tickets; this does not implement
Asahi's complete whole-batch readiness/credits or queued staging model.
Modern ABI/VM/GEM/Mesa and the remaining listed areas stay open. No native GPU
execution, Vinix boot, reboot or deployment occurred. Host synchronization and
firmware services remain injected; these checks do not measure whole-kernel leaks.

The complete evidence bundle is
`/Users/alex/.local/state/vinix/omarchy-m1-event-admission-20261115/bundle/`.
Its sibling `inventory.json` SHA-256 is
`922efe4671b912c81cd0f955515c88ff7c4ce273e6f24de22787448759c3bffc`.
The sibling `bundle.tar.gz` SHA-256 is
`86763685d5f577a73bd413f20e80e07a9a1bf433105f54a5981bf132b258e389`.
Canonical and fully extracted bundles pass the unchanged inventory checker.
Linked kernel SHA-256 values are
`3cc7445f9cb1d593719adfe7aa604c05787edbb1de169943b6101f60c43603b3`
(AArch64) and
`3a459f9ba3c901c582ebe4f3dd372174c6273b770a3889581a8820a1b4f91bef`
(x86_64).

## Earlier artifact retention incident

The continuation initially reused the earlier `omarchy-m1-20261114/kernel-build`
directory and replaced its linked AArch64 kernel. The original `evidence.json`
and source snapshots were preserved. Its receipt still has SHA-256
`90ec316389365996535dfbb98a101bff6b56315887d32ecd6602d34a89eae47a`, but the
kernel at that path no longer matches its recorded
`cfebef4ef9d87345e9e9a984d1ea526dd2f5ee5fc181dd282b23c7e831de3e0e`.
The original complete evidence bundle therefore cannot currently pass integrity
verification. This report does not replace that checksum, weaken its check, or
claim restoration of the missing binary. The new builds and receipt use a
separate directory.
