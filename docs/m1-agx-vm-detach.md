# VM namespace removal and retained ownership

Native `VM_DESTROY` now removes the userspace VM name even while queues,
accepted jobs or mappings exist. Previously these owners caused `EBUSY`.
Repeat destruction and new VM-name lookups return `ENOENT`. Existing queues
retain their physical context and can pass submission lookup after its name
has disappeared, including when destruction races unlocked command copying.

This follows the packaged Asahi
[VM removal and queue cloning](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs).
Its file-owned VM drop removes user mappings while queues retain independent
VM and driver-allocator clones. The reference
[unmap path](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/mmu.rs)
can defer removal or commit through its GPUVM/mapping guards.

Vinix retains physical contexts in the existing file ownership array. An
inline 64-byte bitmap separates removed names from those owners. New queues,
private GEM creation and user BIND/UNBIND retain visible-name lookup. Mapping
retirement and submissions through existing queues use physical-owner lookup.
Bounds checks precede bitmap indexing, and creation/removal reset its slot.
VM-private BO reservation identity remains a non-reused scalar, independent
of physical context-slot reuse.

The file-locked VM reaper waits for aggregate jobs to become idle, then removes
all detached user bindings through the existing acknowledged-unmap path.
Failed invalidation retains mapping records, BO references and the context.
Logical queues and G13 resource owners, including failed-create quarantine,
retain driver mappings and prevent physical context destruction. Captured
queue references keep those arrays installed before registration acquires its
original aggregate VM pin. Queue destruction and the open-file worker retry
VM retirement; Handle close continues using the existing closing-file path.
Final file close, callback retirement and physical UAT teardown are unchanged.
Independent lifetime review found no blocker. No metadata free was added.

This qualifies the namespace/ownership split, not complete VM-close equivalence.
Vinix defers user unmaps until aggregate jobs are idle rather than reproducing
Linux reservation-fence scheduling. Failed-create quarantine owners remain
retained until file close. VM handles still correspond to a bounded set of
physical UAT slots. Native close timing, heap rates and hardware behavior
remain unqualified.

Validation passed:

- 600 host sanitizer ownership cases execute actual VM/queue destruction,
  mapping cleanup and registry reaping. They cover aggregate pins, live queue
  captures, repeated removal, private-GEM/queue/BIND/UNBIND lookup errors,
  mapping and queue invalidation failures, unavailable managers, untouched
  sibling mappings, slot reuse and hidden-owner Handle-close retries.
- 200 removals during copying and 200 later submissions through existing
  queues pass the actual submit and pending-worker bodies. This async fixture
  injects the namespace result; the close fixture executes `VM_DESTROY` itself.
  Queue/VM references drain completely, including wider error/stop regressions.
- Seven complete native-file counterexamples compile and fail their intended
  assertions: busy name removal, visible removed names, visible-only mapping
  retirement, lost queue ownership, retained live-BO bindings, missing worker
  retry and visible-only submission lookup. The reusable V runner is in Git.
- All 47 focused V test files, selected reference gates and 140 native storage
  guards plus their allocation-mutation selftest pass. Wait, wire, fence,
  close, async, CPU-cache, VM, sanitized TLB, layout and render regressions pass.
  Fresh sanitizer fixtures pass 30,375 tiling results, 12,000 work images,
  14,400 timestamp images and 48,000 start/finalize images.
- Fresh isolated ARM and x86 kernel builds pass. Generated-C review confirms
  unchanged preparation/cleanup/reapers, publication, final file close,
  pending/callback retirement, queue reference transfer and UAT teardown.
  Submission/mapping retirement change only their VM lookup; cleanup selects
  detached user bindings, creation resets visibility, and queue/registry
  retirement adds VM retry. Four namespace/lookup/reaper helpers allocate
  nothing. x86 C matches baseline after normalizing compiler discard-variable
  path hashes; both executable identities are retained separately.

Baseline and changed allocation audits retain the existing allowance failure
at 381 ARM / 289 x86 sites. Source counts remain 830 / 813 and per-file,
per-kind counts match. No allowance or historical checker changed.

Fresh heads remain Omarchy `7c8e05925391188d6e95e581dc51c12fb2facd48` and packages
`4cbfbc706efdf98fbe644f9ae7fa0cf18304530c`. Selected package definitions are
unchanged. Pins remain Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The fresh full audit still reports
**not_equivalent** (exit 1); selected gates pass. Modern ABI/Mesa integration,
reservation fences, cumulative timelines, remaining wire/default coverage,
topology and power/reset gaps remain alongside the VM differences above.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-vm-detach-20261116/`.
Source baseline is `a5e91ca5cedfaab539c14aa4fcf9fdcdc1afaa1d` plus the retained
18 source paths, including one native overlay for each build. The complete
prior bundle, current canonical bundle and archive restoration pass the
unchanged typed inventory checker. Retained source copies, C/ELFs, executables,
diagnostics, counterexamples and lifetime review remain outside Git. `completion.txt`
binds the 18 sources and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `047c16bae75c98ef0d1e417cf9c754846419b2ef3a1dc47c7a19a166aed27e1c` |
| `bundle.tar.gz` | `284ad83a1a699a4b1180ef088711e1a0a116d9b727ef478f1f9c2a34abafd65c` |
| `bundle/vinix-aarch64` | `0f331c024ee1097db5969fe1f12f820ecbbde4b971cef94491c1a6a5345b7518` |
| `bundle/vinix-x86_64` | `4cd60bc07379347f4eab48bbb28f6a9ff78e5e81f989b660eb34e9b66ed7cf2f` |
| `bundle/blob-aarch64.c` | `754d189612f9881640b2cfa3432c98b2d3c16dd626ef2741323a06452b7cde09` |

No hardware workload, Vinix/QEMU boot, reboot, SSH or deployment occurred.
