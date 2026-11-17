# Validate render scratch after G13 queue construction

Modern QUEUE_CREATE now checks a nonzero render-scratch layout after resolving
the VM and constructing the G13 queue. Previously the adapter rejected it first.
A request with both an unsupported layout and a missing VM now returns ENOENT;
constructor allocation failures return ENOMEM before the eventual EINVAL for
the layout. Valid zero-layout creation retains its USC base and priority policy.

This matches `file.rs::queue_create` and the default
`Queue::reserve_render_scs` in packaged Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. The default accepts only zero
layouts; the shared G13 queue implementations have no override. Header/priority
validation still precedes VM lookup. The isolated Vinix baseline is
`d517147354c765f18b77d98d91c8be13cd4d76c1`, with only
`kernel/gpu/agx/file/file.v` and `modern.v` overlaid. Concurrent event-manager
edits are excluded.

An unsupported layout never publishes a logical name or overwrites the output
queue ID. Rollback destroys and frees the unpublished logical record. Successful
backing release permits subsequent G13 metadata disposal; failed invalidation
keeps an orphan owner, preserving the graph, VM and queue ID until the existing
worker or close retry completes. Independent lifetime review requested this
logical-before-G13 metadata order; the corrected implementation has no blocker.

Passed offline checks:

- The complete sanitized file-close suite, including 750 new registered-node
  cases covering validation/allocation precedence, partial construction,
  cleanup, VM removal, unavailable manager, ID reuse and zero-layout success.
  The fixture frees actual heap logical records and checks ASan shadow state.
- Three compiled negative variants fail designated precedence, logical-free
  and orphan-owner assertions. Compilation failures do not qualify.
- Six warmed batches of 1,000 rejected creates retain zero host malloc blocks
  and bytes for immediate and retried cleanup. These are host measurements;
  the injected GPU constructor uses pool records, not native firmware backing.
- Pinned Rust source ordering and default-trait comparison, with complete
  relevant source bytes retained. Rust and firmware are not executed.
- Isolated AArch64 MP and x86_64 builds. ARM generated C changes only the
  constructor helper, its two callers and helper prototype after compiler
  discard-path normalization. Rollback retains or disposes the correct owners,
  and these bodies introduce no hidden allocation. The original 18-body modern
  adapter guard passes; the original strict x86 comparison also passes.
- Every allocation file/kind count and architecture total matches the prior
  baseline: ARM 377 sites across 839 sources, x86 289 across 813. Existing
  allowance failures remain; no allowance or historical-checker changes.

Native first release normally defers context retirement. The fixture's
immediate-release success does not establish synchronous native cleanup. This
increment closes the specific render-SCS validation-order gap; constructor,
namespace limits and complete scheduler/firmware behavior remain unqualified.
Full parity is still incomplete: purge advice requires safe backing exclusion
and invalidation, native timelines remain noncumulative, and Mesa migration and
hardware acceptance remain open. No GPU access, firmware execution, Vinix/QEMU
boot or reboot occurred.

The complete evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-queue-scs-20261117/bundle/`.
It includes baseline/current C, both ELFs, V input inventories, source snapshots,
test executables, reference sources, negative cases, diagnostics and review.
The preceding original archive is checked unchanged. Full restoration and both
named archive roots are checked; a post-commit receipt binds feature bytes.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `e7f35b24d04044d08e737247c94236560628678eb42137bad555c02199a01af3` |
| `bundle.tar.gz.inventory.txt` | `7e353d00ad44aa760235adcfa691e3cf08f2eeb3ee8b7b997381d951f1f1a351` |
