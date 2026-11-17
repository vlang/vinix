# DRM timeline WAIT

Vinix registers `DRM_IOCTL_SYNCOBJ_TIMELINE_WAIT` (`0xc03064ca`) with the
48-byte UAPI layout. It snapshots handles, object identities and points before
waiting. Initial validation examines every entry, including entries after an
already-ready ANY candidate. Zero points snapshot the current head; null points
mean zeroes. Positive points resolve cumulative chains and completed retired
prefixes. AVAILABLE waits for publication; ordinary waits require completion,
including error completions. ALL/ANY and first-signaled output follow Linux's
reviewed paths, including ALL retaining its initial first-ready index.

Future-point capture uses a separate intrusive list in each retained syncobj.
Initial validation does not register unresolved points. Arming rechecks under
the publication lock, then borrows the request's node. Publication captures
the first suitable fence and detaches that node under the same lock. Reset,
replacement and namespace reuse cannot retarget an existing capture. Every exit
unlinks captures before freeing capture/point/optional-handle storage. Resolving
under the object lock reads immutable chain links and atomic completion bits;
it takes no fence lock or callback. Existing binary captures keep their path.

Reference: packaged Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. Isolated Vinix builds use
`d3ae11cef54ea7f2ea493ce02e4e86960817dbb6` plus six owned kernel overlays;
concurrent event edits are excluded. Passed offline checks:

- 1,824 counted WAIT checks, including all request-owner OOM positions through
  4096 entries, copy/validation failures, future-point timeout/interruption/
  completion cleanup, masked/unmasked/shared signals and exit, errors, reset,
  replaced names/user arrays, deadlines and publication between snapshot/arm.
  Free hooks reject request storage still reachable from an object. Additional
  protocol checks distinguish unavailable versus retired completion captures.
- All 21,952 zero-timeout results match compiled unchanged pinned Linux WAIT
  timeout/array/ioctl and chain init/walk/find/signaled bodies: seven head states
  per object, four point triples and all sixteen valid flag combinations. Host
  allocation/refcount/RCU/usercopy, callback/publication and scheduler plumbing
  are stubs; native scripted race evidence is separate. The oracle rechecks the
  unchanged complete preceding SIGNAL bundle before reusing its infrastructure.
  Linux errno values are explicit because Darwin's `ETIME` differs.
- Full DRM regressions pass ASan/UBSan with kernel GC mode and stack-use-after-
  return detection. Three compiled negatives fail designated capture-unlink,
  availability and initial-snapshot assertions. All 74 isolated source-contract
  files pass, including new cleanup/publication/registration negative controls.
- Nine warmed 1,000-cycle malloc-zone batches at 1/65/4096 future-point handles
  retain zero host blocks/bytes. This measures freed request ownership only;
  published metadata retention and native slab rates remain open.
- AArch64 MP and x86_64 builds pass. Generated C rejects hidden allocations in
  wait/capture/registration bodies and confirms two table owners, stack inline
  tables and detach-before-free order. Publication adds only the timeline list
  notification. Twenty-eight existing completion/binary/query/signal bodies
  match baseline; ARM's point-lookup inner logic matches too. The old unused
  x86 point-lookup wrapper was pruned. Independent source/C lifetime review
  found no blocker.
- Allocation diagnostics remain 377 ARM / 289 x86 sites across 846 / 819 source
  files. Every file/kind count matches the preceding build. Existing allowance
  failures remain, with no allowance-list changes.

Full parity remains **incomplete**. Vinix polls/yields instead of using Linux
fence callbacks, wait scheduler hints and util-min scopes. Deadline flags are
accepted without leaf scheduling support. Jiffy timeout rounding, actual
multi-CPU behavior and native performance are unqualified. Inline/combined
handle storage differs from Linux's two allocations, including combined-invalid
OOM/fault precedence. Transfer, legacy timeline interoperability, published
metadata reclamation, containers/merge, Mesa, firmware/cache lifecycle and
hardware acceptance remain open. The generic timeline capability stays disabled.
No GPU access, firmware execution, Vinix/QEMU boot or reboot occurred.

Maintained [tests and runners](../tests/drm-timeline-wait/README.md) stay in Git.
The complete source/evidence bundle, native C/ELFs, primary reference bodies,
sanitized executables, negative controls, memory probe, contract sources and
review are retained at
`/Users/alex/.local/state/vinix/omarchy-m1-timeline-wait-20261117/bundle/`.
Complete archive restoration and both named roots are checked. A post-commit
receipt binds the committed feature bytes to sealed source.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `765a9fa50928b062fed47afe1696e294984519957f18bfd9b64041168a6e3e1a` |
| `bundle.tar.gz.inventory.txt` | `394aa69ff771bd20bf080126ab36de6ca0f1deb1013765d4bb6cd9758317414e` |
| ARM ELF | `2919cbd70b28f10828b2a4d0ff08b35b70b39bad4406e8bbdf92992294f3a570` |
| ARM C | `fc0f46956a2224c7d7d8330d7d71a7a6870e7bcfe4c5ce1150b1583d38bb058b` |
| x86 ELF | `ee7574cff2311df0de5a31804ace3919296499bd7973a6424aadc1bd3d486f27` |
| x86 C | `07b2a98b16a101f618e1906b8bcd7ddff1582cc82abb7b8767ddd958f0366c09` |
