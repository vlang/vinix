# G13 queue namespace removal and retirement

Native G13 `QUEUE_DESTROY` now removes the userspace name immediately, returning
success while accepted jobs remain live. Previously it returned `EBUSY` when
the queue's resources could not yet retire. The packaged Asahi
[file handler](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs)
removes the namespace entry independently of accepted work; its
[subqueue jobs](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs)
retain their workqueue through an `Arc` clone.

Both native submission lookups hide detached names. New submissions and repeat
destruction return `ENOENT`; already accepted jobs keep running and can finish
their dependency waits and callbacks. Physical queue ownership remains in the
file's existing arrays until aggregate VM pins reach zero and the original
cache-safe invalidation/release succeeds. Retained IDs remain reserved until
that retirement, preventing a new queue from aliasing the old graph.

The GPU worker retries detached open queues after processing pending nodes.
Registry locking pins each open file through nested file/manager locking,
without a new allocation or reference. Handle close removes the registry entry
and transfers outstanding cleanup to the existing closing-file path. Failed
invalidation or unavailable managers keep ownership intact. Independent
lifetime review found no blocker; command preparation, retirement, final file
close and physical release retain their previous implementation.

This is deliberately a partial lifetime port. Pins are VM-wide, so unrelated
work in the same VM can retain a detached queue longer than Asahi's per-queue
owners. A queue destroyed during unlocked user-copy staging can still return
`ENOENT` at locked revalidation; Vinix does not capture Asahi's initial `Arc`.
`VM_DESTROY` retains its existing busy-owner behavior. Queue/resource metadata
keeps its baseline lifetime; no metadata free was introduced.

Validation passed:

- 2,400 sanitizer cases execute actual queue destruction, namespace probing,
  ID allocation, registry reaping and Handle-close transfer. They cover live
  aggregate pins, unavailable managers, repeated invalidation failure/retry,
  repeat destroy and registry/file lock ownership.
- 200 asynchronous cases execute the actual ioctl lookups and pending worker.
  Accepted jobs survive namespace removal and input dependencies; detached
  names reject before staging and at revalidation after removal during copying.
  The last callback leaves the aggregate VM pin alive until worker retirement.
- Four complete native-file counterexamples compile and fail the intended
  assertions: busy destruction, premature physical release, visible detached
  names and missing retry. The reusable V runner remains in Git; full variants,
  executables and failures remain in the external bundle.
- All 45 V test files, selected source gates and 132 native storage checks plus
  their allocation-mutation selftest pass. Wait, wire, fence, close, asynchronous
  ownership, CPU-cache, VM, sanitized TLB, layout and render regressions pass.
  Fresh sanitizer fixtures also pass 30,375 tiling results, 12,000 work images,
  14,400 timestamp images and 48,000 start/finalize images.
- Fresh isolated ARM and x86 kernel builds pass. The initial x86 link attempted
  macOS's platform linker; the preserved retry uses `LD_X86_64=ld.lld`.
  Generated-C review confirms unchanged native preparation/cleanup/reapers,
  batch publication, pending-node/callback retirement, final close and manager
  release. Submission bodies differ only by detached-name exclusion; service
  adds the open-file reaper. Both new helpers allocate nothing.

Baseline and changed allocation audits both retain the original allowance
failure at 381 ARM / 289 x86 sites. Source counts remain 830 / 813 and per-file,
per-kind counts match. No allowance or historical checker changed. Native heap
rates, physical cache coherence and hardware behavior remain unqualified.

Fresh heads are Omarchy `7c8e05925391188d6e95e581dc51c12fb2facd48` and packages
`e2bd1f19abf1c09e1c9233e0e1b3df616016e15e`. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The full fresh audit still reports
**not_equivalent** (exit 1); selected gates pass. ABI/Mesa, VM ownership,
reservation fences, cumulative timelines, remaining wire/default coverage,
topology and power/reset gaps remain.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-queue-detach-20261116/`.
Source baseline is `1fa8bc980d167cfb21e0540a0635c7ed316343b4` plus the retained
17 source paths, including three native overlays for each build. The complete
prior bundle, current canonical bundle and archive restoration pass the
unchanged typed inventory checker. Native C/ELFs, sources, runners, diagnostics,
counterexamples and lifetime review are retained. `completion.txt` binds the
17 sources and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `433616a8592d02f425167f8f7c4fecaf29c8ba0fd79b5970191080116dbcbfae` |
| `bundle.tar.gz` | `ca85595b942572ca76861733daab0bafa878c70b6af2b6a07c6a925a8d6d68e6` |
| `bundle/vinix-aarch64` | `fbcff6a48465b789685add05c0e1a00ec9165933881c2956ef20f8cbf0092c4a` |
| `bundle/vinix-x86_64` | `a1e3156c267a39004da9f84f1a23c4380b591b0b41f74ffe9c57b5ccf726fa3b` |
| `bundle/blob-aarch64.c` | `69e8785635ef9fb90b9ff5af5c4196f19ac17b62bb6b921ab980c31080c62475` |

No hardware workload, Vinix/QEMU boot, reboot, SSH or deployment occurred.
