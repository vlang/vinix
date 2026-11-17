# DRM transfers to binary syncobjs

Vinix registers the 32-byte `DRM_IOCTL_SYNCOBJ_TRANSFER` (`0xc02064cc`) and
implements destination point zero. The destination is looked up before the
source. Source lookup precedes flag validation, matching Linux's combined-error
ordering. Source point zero snapshots the head; positive points resolve the
cumulative chain, and retired prefixes supply the permanent completed stub.
Successful transfer replaces the destination with that exact fence. It waits
for availability, not GPU completion. Errors leave the destination unchanged.

FOR_SUBMIT borrows one explicitly allocated stack capture, rechecks publication
under the object lock and waits up to five seconds. Captured object/fence
metadata retains its existing lifetime through reset and namespace reuse.
Every prepared return unlinks the capture before its stack frame ends, with no
object or fence lock held while yielding. The host retention probe caught V
boxing both an ordinary local and a fixed-array variant onto the heap; the
kernel's existing `__builtin_alloca` pattern removes that hidden allocation.
Failed attempts and generated C remain in the external state directory.

Reference: packaged Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. Isolated Vinix builds use
`1625440897e2116677c4b09adb7f51761d498e0b` plus four owned kernel overlays;
concurrent event changes are excluded. Passed offline checks:

- 1,221 counted transfer checks and the full ASan/UBSan DRM regression suite in
  kernel GC mode with stack-use-after-return detection. Cases cover pad/name/
  flag precedence, pending and retired points, cumulative chains, self-copy,
  destination publication, exact source/destination identities through name
  reuse, five-second timeout, signals, publication before arm and cleanup before
  later publication. Three compiled negatives fail designated capture-cleanup,
  exact-payload and source-point assertions.
- All 10,752 outcomes match compiled unchanged pinned ioctl dispatch, binary
  transfer, find-fence, add-wait and chain bodies. Cases cross seven head states,
  six unsigned source points, all sixteen flags, missing names, pad and self-copy.
  Refcount/RCU/usercopy/publication and one-step timeout scheduler plumbing are
  host stubs. Future-publication/interruption cases are separate native-fixture
  evidence. The oracle never selects timeline destinations and rechecks the
  unchanged complete preceding WAIT bundle before reusing infrastructure.
- Nine warmed 1,000-cycle host success/timeout/interruption batches retain zero
  malloc blocks and bytes. This measures request ownership, including the
  implicit allocations the fixture allocator cannot see. Published metadata
  and native slab retention/performance remain unqualified.
- All 75 isolated source-contract files pass, with new registration, validation,
  initialized-stack, availability and cleanup guards plus negative controls.
- AArch64 MP and x86_64 builds pass. Four transfer/registration C bodies reject
  hidden allocations. The lookup contains exactly one explicit initialized
  stack capture and detaches it on all prepared exits. Twenty-seven existing
  completion/capture/wait/query/signal bodies match baseline. Independent
  source/generated-C lifetime review found no blockers.
- Allocation diagnostics remain 377 ARM / 289 x86 sites across 848 / 821 source
  files. Every file/kind count matches the preceding WAIT build. Existing
  allowance failures remain, with no allowance-list changes.

Full parity remains **incomplete**. Positive destination points return
EOPNOTSUPP after pad validation, until timeline-destination merge/container
semantics are implemented; those requests and their error precedence are outside
the compared subset. The generic timeline capability remains disabled. Native
poll/yield behavior differs from Linux callback scheduling and jiffy rounding.
Actual multi-CPU behavior, legacy timeline-map interoperability, published
metadata reclamation, Mesa, firmware/cache lifecycle and hardware acceptance
remain incomplete or unqualified. No GPU access, firmware execution, Vinix/QEMU
boot or reboot occurred.

Maintained [tests and runners](../tests/drm-binary-transfer/README.md) stay in Git.
The complete source/evidence bundle, primary reference bodies, native C/ELFs,
sanitized executables, negative controls, memory probe, contract sources and
review are retained at
`/Users/alex/.local/state/vinix/omarchy-m1-binary-transfer-20261117/bundle/`.
Complete archive restoration and both named roots are checked. A post-commit
receipt binds committed feature bytes to sealed source.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `7090e1958e191249bdc32ed4117b83e049cacf0ea7aa134f18f4a53d77ef7862` |
| `bundle.tar.gz.inventory.txt` | `4a98ade5feb0fca6b16cb7e537a10e55619118b86311c1b20e945accb5a3fbbf` |
| ARM ELF | `c6c2a9aef1bafb88575d3fc04e57eeb7034ce7f8a2f13dbe1e42d6031def3304` |
| ARM C | `f37d8a02b498f354cb246b65ebe9e2027b724e6311790245d7c1e062109bdb6d` |
| x86 ELF | `4e637d46b6ae7966faedaeaf8e0fcc0485a374f42118a17d6231ad029b10282a` |
| x86 C | `f179d4110e7c05234285c8656765ae8767732159ec183e3c125249ae76594e55` |
