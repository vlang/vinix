# DRM timeline SIGNAL

Vinix now registers `DRM_IOCTL_SYNCOBJ_TIMELINE_SIGNAL` (`0xc01864cd`), using
the 24-byte timeline-array layout. It snapshots every object identity and point,
then reserves every chain node before publishing anything. Null points mean an
array of zeroes. Zero, repeated, decreasing and full-width unsigned points use
the existing cumulative-chain rules. A successful SIGNAL payload does not
complete earlier unfinished GPU work; previous errors do not overwrite the
chain's successful completion once its prefix finishes.

Timeline SIGNAL uses a permanent, already-completed global stub with zero
context/sequence and one stable timestamp, like Linux's `dma_fence_get_stub`.
Vinix initializes it during first DRM driver registration, with a locked getter
fallback. Binary SIGNAL and CREATE retain their distinct private completions.
No allocation remains after publication begins. Private reservations unwind
before the chain-pointer table, points and optional handle buffer; published
metadata retains the existing lifetime. Independent lifetime/C review found no
blocker, including first captures and namespace reuse during publication.

Reference: packaged Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. The isolated Vinix baseline is
`8f0622c7515265ef5762b8d8ced20d8ed510c0b8` plus four owned kernel overlays;
concurrent event-manager edits are excluded. Passed offline checks:

- 302 counted allocation/copy/lookup cases, including every failure position
  through 129 outputs. Every failed reservation leaves heads unchanged and
  releases its private prefix. Success reaches 4096 nodes. Additional tests
  preserve pending predecessors, shared-stub identity/time/status, first-fence
  captures and snapshotted points/objects across exact-lock handle reuse.
- All 15,552 readiness/progress results match compiled pinned Linux SIGNAL and
  QUERY handlers with unchanged chain init/walk/signaled bodies. Cases cover
  unsigned triples, null points, repeated/distinct objects and nil/pending/
  completed binary predecessors. Allocation, refcount, RCU, usercopy and
  add-point publication plumbing are single-thread host stubs; timestamp timing
  and actual concurrency are unqualified. The oracle rechecks the preceding
  complete QUERY bundle before reusing its plumbing.
- The full DRM suite passes ASan/UBSan in kernel GC mode with stack-use-after-
  return detection. Three compiled negatives fail designated reservation cleanup,
  pending-prefix and null-points assertions. All 73 isolated source-contract
  files pass, including new reservation, publication, private-stub separation
  and permanent-initialization guards with negative controls.
- Nine warmed 1,000-cycle malloc-zone batches fail the final reservation at
  1/65/129 outputs and retain zero host blocks/bytes. This measures unpublished
  owners only; published metadata retention and native slab rates remain open.
- AArch64 MP and x86_64 builds pass. Four signal/registration C bodies reject
  hidden allocations. Request owners and cleanup are explicit; the getter
  returns permanent storage without allocation. Startup adds only that call.
  Twenty-two existing completion/wait/QUERY/private-stub bodies match baseline.
- Allocation diagnostics remain 377 ARM / 289 x86 sites across 844 / 817 source
  files. Every file/kind count matches the preceding build. Existing allowance
  failures remain, and the allowance list is unchanged.

Full parity remains **incomplete**. Vinix uses inline/combined handle storage
instead of Linux's two allocations; combined-invalid OOM/fault precedence is
different. The permanent stub's initialization phase is first DRM registration,
where Linux uses subsystem initialization. Timeline wait and transfer remain
unfinished, so the generic timeline capability stays disabled. Legacy map
interoperability, published metadata reclamation, merge/containers, Mesa,
firmware/cache lifecycle, actual multi-CPU behavior and hardware acceptance
remain incomplete or unqualified. No GPU access, firmware execution, Vinix/QEMU
boot or reboot occurred.

Maintained [tests and runners](../tests/drm-timeline-signal/README.md) stay in Git.
Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-timeline-signal-20261117/bundle/`:
source, host executables/C/logs, pinned references, negatives, memory probe,
isolated source contracts, native C/ELFs/inventories and review. Complete archive
restoration and both named roots are checked. A post-commit receipt binds the
committed feature bytes to the sealed source.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `96e7024b318cfeebe29ff6225e5977a1f876cbdbd8d790156569852544b992f9` |
| `bundle.tar.gz.inventory.txt` | `98fd5d3531d6ed559f3fbfefbc635f3a634d3f9391c349da8e423ced0a72af46` |
| ARM ELF | `7fda2017d9704c6f0a73bb0653b88d95a205e1178ee876a54018b54f3119d932` |
| ARM C | `35c96b7e11668921fbeda504c12d7095eeb927780599f849caab71de86482c6d` |
| x86 ELF | `ca5af53924ba7d5f37be4f33e2e19d37d3c682fbe344148a7eeaa6542fcdf84e` |
| x86 C | `ab309e2e286e3f3962a951e283eb255992bb90550d49d89f9a0dec3763af2caf` |
