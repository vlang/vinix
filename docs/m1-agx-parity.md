# M1 AGX parity with Omarchy

Status: **incomplete**. Reference: the Asahi driver in Omarchy's packaged
Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`. The source chain and
original comparison are in [the initial port report](omarchy-m1-gpu-port.md).
Same firmware protocol is the target; identical Linux/Rust source is not a
meaningful requirement for a V kernel with different memory and scheduler APIs.

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
| Submission scheduling | Vinix accepts at most two commands in the compute-then-render form and waits on dependencies in the ioctl. The reference accepts general batches through DRM scheduling, with multiple in-flight jobs and per-subqueue barriers. |
| Render scenes | Vinix retains one active render scene per queue. The reference manages scene slots and shared TVB lifetime across overlapping work. |
| TVB ownership and growth | Complete staged heap extension is implemented below. Vinix still retains its slot for the queue's lifetime; the reference uses scene-bound slot ownership. |
| VM binding | Vinix uses individual contiguous bindings with strict overlap rejection. The reference has batched, extensible VM operations, mapping replacement/splitting, scatter backing and integration with DRM GPUVM/reservation fences. |
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
active Mesa 25 ABI and two-command scheduler therefore remain gaps. The
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
