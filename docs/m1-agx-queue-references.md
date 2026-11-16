# Captured G13 queue ownership

G13 submission now captures an owned queue snapshot before copying commands
and syncs, matching the packaged Asahi driver's initial
[queue Arc clone](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs).
Destroying the queue during copying hides its name while the captured submit
continues with the original VM, capabilities and resources. New lookups return
`ENOENT`. Previously a second namespace lookup could reject the captured call.

Each captured ioctl holds one atomic queue reference. The outer cleanup drops
it on every pre-registration error; accepted registration transfers it to the
pending node. Final fence/callback work completes before the worker releases
the queue reference, drops the aggregate VM pin and frees the node. Detached
queue retirement now checks its own references, so unrelated work in the same
VM cannot delay that queue's cleanup. Normal manager release also checks the
counter before releasing physical backing.

The capture leaves VM job admission unchanged during copying. Queue ownership
remains installed, preventing VM destruction; the ioctl's retained Handle pins
the file. The original late VM increment and registration-failure decrement
remain. Independent review caught and rejected an earlier design that pinned
the VM before copying because it blocked the submit's own retired-mapping
cleanup. Final lifetime review found no blocker. Stopped teardown retains
metadata so a later captured-reference release remains safe; no metadata free
was introduced.

Validation passed:

- 2,400 sanitizer queue-retirement cases cover independent queue references,
  unrelated VM pins, unavailable managers, failed invalidation/retry, hidden
  names, ID isolation, registry/file locking and Handle-close transfer.
- 200 accepted jobs survive namespace removal and dependencies, and 200
  additional captures survive removal during copying. The copy hook checks
  that VM inflight remains zero while the queue is retained. The wider async
  suite verifies reference balance across staging, lookup, device-loss,
  registration, callback and shutdown failures. Removal during copying also
  completes with the original timestamp/result owner.
- Eight complete native-module counterexamples compile and fail assertions:
  busy destruction, VM-wide retention, visible detached names, missing retry,
  missing capture, missing error cleanup, missing ownership transfer and
  missing final release. Their V runners remain in Git.
- All 46 V test files, selected source gates and 136 native storage checks plus
  their allocation-mutation selftest pass. Wait, wire, fence, close, async,
  CPU-cache, VM, sanitized TLB, layout and render regressions pass. Fresh
  sanitizer fixtures pass 30,375 tiling results, 12,000 work images, 14,400
  timestamp images and 48,000 start/finalize images.
- Fresh isolated ARM and x86 kernel builds pass. Generated-C review confirms
  unchanged preparation/cleanup/reapers, publication, mapping cleanup,
  registration, final file close and syscall Handle lifetime. Manager release
  adds only the reference guard and deferred-unlock temporaries; retirement
  adds only the final queue release. Five capture/reference helpers allocate
  nothing. x86 C matches baseline after normalizing compiler discard-variable
  path hashes; executable identities are retained separately.

Baseline and changed allocation audits both retain the existing allowance
failure at 381 ARM / 289 x86 sites. Source counts remain 830 / 813 and per-file,
per-kind counts match. No allowance or historical checker changed. Native heap
rates, physical cache coherence and hardware behavior remain unqualified.

Fresh heads are Omarchy `7c8e05925391188d6e95e581dc51c12fb2facd48` and packages
`4cbfbc706efdf98fbe644f9ae7fa0cf18304530c`. The selected package definitions
are unchanged from the preceding pass. Pins remain Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The fresh full audit still reports
**not_equivalent** (exit 1); selected gates pass. Modern ABI/Mesa integration,
VM destruction ownership, reservation fences, cumulative timelines, remaining
wire/default coverage, topology and power/reset gaps remain.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-queue-references-20261116/`.
Source baseline is `3582195cf3ca854fec4703abe24610f06c20abf3` plus the retained
25 source paths, including three native overlays for each build. The complete
prior bundle, current canonical bundle and archive restoration pass the
unchanged typed inventory checker. Native C/ELFs, sources, runners, diagnostics,
counterexamples and lifetime review are retained. `completion.txt` binds the
25 sources and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `a99ff6c02b7579b4946dfdf539e21fb61a913f8ec5cbfaa17052d9820acb70c7` |
| `bundle.tar.gz` | `356c9cb29065c3f418755a4304a60364f6146fa1ca12aad8785fa8313d4fc697` |
| `bundle/vinix-aarch64` | `44e9f86e53ea6b20cecb4988bda03c4949810e964e9d73003db2faee9242f7c1` |
| `bundle/vinix-x86_64` | `09dd5931754d1df8ade6453cb12eb9a9f0981774f3e1faf70166111c6681a3b1` |
| `bundle/blob-aarch64.c` | `344a1160ac05c536a0220d8f0daa329b8f400c5abf73d5b672a18d65bd7528cb` |

No hardware workload, Vinix/QEMU boot, reboot, SSH or deployment occurred.
