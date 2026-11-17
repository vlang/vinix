# DRM timeline QUERY

Vinix now registers `DRM_IOCTL_SYNCOBJ_QUERY` (`0xc01864cb`) with the pinned
24-byte timeline-array layout. It reports either completed timeline progress
or the head's sequence with `LAST_SUBMITTED`. Empty/binary objects return zero;
unordered context boundaries stop completed-progress traversal. It uses the
modern cumulative chains added in the preceding increment.

The handler snapshots all handles and object identities before writing any
point, then samples the current fence head per output entry, as Linux does.
Publication between repeated handles can change a later result. Handle removal
and reuse cannot redirect a captured object pointer. Later output faults retain
the already-written prefix, including Linux-style partial copies within a u64.
Owned request storage is released on every exit. No new persistent metadata or
reclamation is introduced. Independent lifetime review found no blocker.

Reference: packaged Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, whose Asahi driver enables generic
timeline syncobjs. The isolated Vinix baseline is
`0b9e112f8982754269b845809f1a6a73b486ff81` plus four owned kernel overlays;
concurrent event-manager changes are excluded. Offline validation passed:

- 7,400 counted handler checks plus empty/binary/legacy-map and invalid-pointer
  controls, covering 1/64/65/129/4096 handles, reverse completion/errors,
  flags/count validation, copy/lookup/OOM cleanup, first/middle/last and partial
  output faults, head publication and namespace reuse between outputs.
- All 10,368 production query values match compiled, unchanged Linux QUERY and
  chain init/walk/signaled bodies, across all triples of six unsigned boundary
  values, completion masks and binary predecessor states. Allocator, refcount,
  RCU, feature and usercopy plumbing are single-thread host stubs. The oracle
  checks the preceding complete chain bundle before reusing its plumbing.
- The full DRM wait/sharing/sync-file suite passes ASan/UBSan with
  `-gc none -manualfree` and stack-use-after-return detection. Three compiled
  negatives fail designated progress, owned-buffer cleanup and lookup-before-
  output assertions. All 72 isolated contract test files pass, including QUERY
  registration, dispatch, capability, progress and cleanup negative controls.
- AArch64 MP and x86_64 builds pass. Four query/registration/dispatch bodies have
  no hidden allocation; nineteen existing chain/completion/binary-wait/storage
  bodies match the preceding generated C. Whole-x86-C equality is not claimed.
- Allocation diagnostics remain 377 ARM / 289 x86 sites across 842 / 815 source
  files. Every file/kind count matches the preceding build. Existing allowance
  failures remain, with no edits to the allowance list.

Full parity remains **incomplete**. Vinix keeps inline request storage through
64 handles and one combined allocation beyond it, whereas Linux uses two
allocations; OOM/fault precedence is not equivalent. The generic timeline
capability stays disabled until wait/signal/transfer are implemented. Legacy
map interoperability, containers/merge, published metadata reclamation, Mesa
migration, firmware/cache lifecycle, actual multi-CPU races and hardware
acceptance remain incomplete or unqualified. No GPU access, firmware execution,
Vinix/QEMU boot or reboot occurred.

The [test directory](../tests/drm-syncobj-query/README.md) contains maintained
runners, fixtures, oracle and checkers. Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-syncobj-query-20261117/bundle/`.
It includes final host programs/C/logs, pinned reference sources, baseline test
sources, isolated contract sources, C/ELFs, allocation inventories and review.
The complete archive is restored and both named roots checked. A post-commit
receipt binds committed feature bytes to the sealed source.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `a5c8eb6c05be0408926704c2444a514736ab6f16ae521bae5b4b696817276c67` |
| `bundle.tar.gz.inventory.txt` | `6404d40f632ab7cdcaa7fedd94d02d10ab523cf780da85522ca45f09df016b2c` |
| ARM ELF | `904ed0aee969b1301ffab291f543b004a8598601c9f9586416203cf38d750871` |
| ARM C | `6158b41a11cfc730dae950f0fda2cacc34cd08af6f8b6204a9e4690fbab1e294` |
| x86 ELF | `e56bfb403e5d9bae9c2b8664278c9d941be61eb0e1f5be2df483e68cf1d5af52` |
| x86 C | `efa6f14a5ad07efc129b8e3c99e781fd697cf65ff5794b25ce371c76bfdec06b` |
