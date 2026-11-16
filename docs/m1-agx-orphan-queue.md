# Failed G13 queue construction cleanup

The open-file worker now retries G13 resource graphs retained after failed
queue construction. Previously they remained attached until Handle close,
even when a later invalidation could succeed. Successful cleanup releases the
reserved queue ID and lets a destroyed VM retire when this was its last owner.
The retry also runs while the VM name remains visible.

The packaged Asahi
[queue constructor](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs)
builds fallible owned locals and partial fields. Its
[file handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs)
publishes the queue only after construction and layout reservation succeed;
errors unwind ownership and the namespace reservation independently of Handle
lifetime. This queue path uses Rust drop semantics, not an explicit queue
construction `ScopeGuard`.

Vinix retries only G13 ownership records whose ID has no logical queue in the
file. Any matching logical ID, including a detached queue, protects its owner.
Captured file references also prevent removal, even if stopped teardown has
already released physical backing. The existing manager release method still
checks its exact jobs, references and invalidation result. Ownership is deleted
only after that method succeeds; failed invalidation or unavailable managers
retain the record, VM protection and ID reservation.

The registry and file locks cover the retry. Construction already holds the
same file lock through failed-resource adoption and successful publication,
so the worker cannot mistake a successful constructor for an unpublished
queue. Retry follows detached logical queues and precedes detached VMs.
Unrelated accepted work in the same VM does not delay cleanup of this graph.
The existing normal and final worker polls provide retry opportunities.
Independent lifetime review found no blocker. No metadata free, new heap owner,
namespace mutation or change to final file close was introduced.

Validation passed:

- 1,200 host sanitizer ownership cases cover idle and busy published neighbors,
  visible/detached names, captured references, unrelated VM pins, invalidation
  failure/retry, unavailable managers, ID reservation/reuse and registry/file
  locking. Another 200 cases release the last owner of a destroyed VM, and
  50 interleaved arrays verify partial progress and exact record deletion.
  A stopped-backing case retains metadata ownership until references drain.
- Seven full native-file counterexamples compile and fail their intended
  assertions: missing retry, ignored logical owner, ignored reference, VM-ID
  comparison instead of queue-ID comparison, VM-wide retention, forgotten
  invalidation failure and deletion of the wrong record. The V runner remains
  in Git; complete variants, executables and failures remain in the bundle.
- All 48 focused V test files, selected reference gates and 141 native storage
  guards plus their allocation-mutation selftest pass. Wait, wire, fence,
  close, async, CPU-cache, VM, sanitized TLB, layout and render regressions pass.
  Fresh sanitizer fixtures pass 30,375 tiling results, 12,000 work images,
  14,400 timestamp images and 48,000 start/finalize images.
- Fresh isolated ARM and x86 kernel builds pass. Generated-C review confirms
  unchanged constructors/adoption, queue/VM destruction, preparation/cleanup,
  publication, callbacks, manager physical release, final close and worker
  service. Registry service adds only the new retry between queue and VM
  reaping. The helper allocates nothing. x86 C matches baseline after
  normalizing compiler discard-variable path hashes; executable identities
  are retained separately.

Baseline and changed allocation audits retain the existing allowance failure
at 381 ARM / 289 x86 sites. Source counts remain 830 / 813 and per-file,
per-kind counts match. No allowance or historical checker changed. Native heap
rates, exact teardown timing and hardware behavior remain unqualified.

Fresh heads remain Omarchy `7c8e05925391188d6e95e581dc51c12fb2facd48` and packages
`4cbfbc706efdf98fbe644f9ae7fa0cf18304530c`. Selected package definitions are
unchanged. Pins remain Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The fresh full audit still reports
**not_equivalent** (exit 1); selected gates pass. Modern ABI/Mesa integration,
reservation fences, cumulative timelines, VM capacity/close scheduling,
remaining wire/default coverage, topology and power/reset gaps remain.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-orphan-queue-20261116/`.
Source baseline is `20d46f38a54f5876ca8f384dd9ac06edc4a1ac95` plus the retained
eight source paths, including one native overlay for each build. The complete
prior bundle, current canonical bundle and archive restoration pass the
unchanged typed inventory checker. Retained source copies, C/ELFs, executables,
diagnostics, counterexamples and lifetime review remain outside Git.
`completion.txt` binds the eight sources and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `42271a04e3c8b1a6989226a3b77b6d56ef0b5b64bdaabb73113f50a822b28983` |
| `bundle.tar.gz` | `8bf791c4e1d0dbcb5f94bfd62c6e23c69576046ec9a71f2fb53764357afd1312` |
| `bundle/vinix-aarch64` | `84f2a5d983db7829c058c4de622de72c0d56e19d8cb7236c17ac57cc9caedfeb` |
| `bundle/vinix-x86_64` | `cd57f9303b8c6a01fcb029dfa906271443167b9a1d519de74a6d3eb755f228d9` |
| `bundle/blob-aarch64.c` | `106e86dc7d1706fb454350edde91637576dc2a2eb389b51c2f9daa80af4124e4` |

No hardware workload, Vinix/QEMU boot, reboot, SSH or deployment occurred.
