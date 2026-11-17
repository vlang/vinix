# M1 AGX parity with Omarchy

Status: **incomplete**. Reference: the Asahi driver in Omarchy's packaged
Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`. The source chain and
original comparison are in [the initial port report](omarchy-m1-gpu-port.md).
Same firmware protocol is the target; identical Linux/Rust source is not a
meaningful requirement for a V kernel with different memory and scheduler APIs.

Latest offline increment: [GPU hole insertion history](m1-agx-hole-order.md)
(2026-11-17). Equal-size eligible holes now prefer the newest insertion, matching
DRM MM for the same insertion/removal stream. Splitting inserts the leading
remainder before the trailing remainder; collection reinserts the coalesced
predecessor hole. Independent history and rank-invariant fixtures pass.
Vinix's descending collection order still differs from the reference's deferred
garbage policy, so complete placement histories and native performance remain
unqualified. The [best-fit GPU virtual-address reuse](m1-agx-heap-reuse.md)
report retains its original evidence.
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
- **TVB growth.** GrowTVBAck carries the current firmware halt counter at
  offset `0x18`, rather than leaving those eight bytes zero.
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

These are implementation gaps, not items certified by a passing source gate.

| Area | Vinix versus the packaged reference |
| --- | --- |
| Userspace ABI | Vinix exposes the Mesa 25.0.5 unstable ABI. The reference uses extensible ioctl structures, a flat command buffer, synthetic attachment commands and different ioctl numbering. They are incompatible. |
| Submission scheduling | Vinix prepares up to 64 mixed render/compute commands through its legacy ABI. In-batch and initial cross-submission dependencies use firmware prefixes. Later batches pipeline after older publication. Native fences from the same queue are elided; other inputs wait for signaling independently of errno. Modern flat-command integration and full admission/backpressure still differ. |
| Queue destruction | G13 queue names disappear immediately. Initial submission capture and accepted nodes retain their own queue through copying, callbacks and final retirement; unrelated work in the same VM does not delay release. Invalidation failures retain backing. |
| VM destruction | VM names disappear independently of queues and jobs. Existing queues retain physical contexts; idle user bindings use acknowledged teardown, and failed invalidation retains backing. Contexts retire after every owner ends. Native close timing, reservation scheduling and physical-slot capacity still differ. |
| Failed queue construction | The worker retries unpublished G13 resource graphs independently of Handle/VM-name lifetime. Logical queues and captured references retain ownership; failed invalidation retains the graph. Successful release returns the reserved queue ID and allows final VM retirement. |
| Render scenes | Multiple prepared and published scenes retain shared backing and conditional binding. Commands and batches on one queue may overlap; individual commands wait for their explicit firmware dependencies. |
| Command ring capacity | Compute and both render subqueues count host-unretired command positions and require Asahi's spare entry before publication. Firmware consumption alone does not release host capacity. |
| Event publication capacity | One-event publication now applies Asahi's strict spare-slot rule to the last-published/host-completed stamp delta. The separate 127-ticket preparation table and whole-batch admission remain different. |
| TVB ownership and growth | Staged extension, scene-bound slots and shared tail-pointer backing are implemented below. Full scheduler backpressure and the remaining render defaults still require comparison. |
| VM binding | Vinix uses individual contiguous/repeated binds with idle overlap replacement and range splitting. Batched extensible operations, scatter backing and DRM GPUVM/reservation-fence integration still differ from the reference. |
| GEM and memory accounting | Purgeable VM-private objects, eviction/madvise, device/client limits and the reference's full reservation-fence behavior are not implemented equivalently. |
| Timestamp UAPI | The reference's per-command timestamp objects and current compact command fields are not wired through Vinix's legacy command interface. |
| M1 family | The native path configures base M1/t8103. The reference also supports t6000/t6001/t6002 M1 Pro/Max/Ultra, including clustering and multiple dies. |
| Telemetry | Vinix drains auxiliary channels but does not expose the reference's full firmware statistics/debug interface. |
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
