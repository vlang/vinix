# G13 submissions after device loss

Native submission now returns ENODEV for an error/stopped GPU at its backend
checkpoint, following the packaged
[Asahi submission crash check](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/mod.rs).
Previously these states returned EOPNOTSUPP. A manager-locked snapshot now
distinguishes device loss from unsupported generation or idle/starting state;
healthy G13 continues normally. The lock is released before file mutation.

This checkpoint follows existing legacy command/sync staging and precedes job
preparation/output publication. Rejection releases the owned staging buffer.
Earlier header, queue, allocation, copy, command and sync errors keep their
native precedence. Modern flat-packet copying, parsing and error ordering still
require a coordinated ABI migration.

Validation passed:

- 57,400 final ASan/UBSan checks cover all five manager states, G13/G17 controls,
  compute/render, input-sync and result combinations, missing manager, staging
  failures, loss during unlocked copying and before state-lock acquisition.
  Refusals preserve pending output-fence identity/status, result bytes and BO
  references, leave no jobs/pins and return staging storage. Healthy G13 controls
  complete and drain. The runner uses its own deterministic lock fixture.
- The exact raw prior `ioctl_submit` method builds and fails with EOPNOTSUPP
  where ENODEV is required. Source, adapter, binary and rejection are retained.
- 36 V source/contract/allocation-tool test files, selected primary-source gates,
  and the strict native ARM C storage checker for 109 helpers plus its selftest
  pass. C review confirms a scalar locked result and deferred buffer release
  before the file lock, with unchanged allocation/free, BO ref/unref and output
  installation site counts. Registration, shutdown, completion cleanup, fake
  submission and global-query status bodies match prior C. No new allocation/free
  owner or retained-borrow lifetime is introduced.
- Existing async/scheduling, lifecycle/BIND/UNBIND/timestamp/GEM/private-BO,
  GET_PARAMS/identity/priority, 167,395 wait/syncobj, wire, fence, VM and production
  PTE regressions pass. PTE tests explicitly use `--sanitize`; async/VM/lifecycle/
  PTE sanitizer linkage receipts are retained.
- Isolated ARM and clean x86 builds use
  `5b477c3b6bf9cb7cf2b0eb4a593102b5365961bf` plus `kernel/gpu/agx/file/file.v`
  and `kernel/gpu/agx/gpu/gpu.v` overlays. Both ELF/C pairs and exact inputs are
  retained. Native AGX is ARM-only; x86 uses `LD_X86_64=ld.lld`.

The unchanged allocation allowance audits **still fail** for baseline and feature,
with identical per-file/kind counts: 383 ARM/289 x86 sites and 828/813 sources.
These compiler counts do not measure native heap rates. No allowance was changed.

Fresh remote heads are Omarchy `87ee744206a416a803696b7c5a2ce91e9ef74dbb`
and packages `e09236d51c9c9735228a050f99823de48f1f9699`. Pins remain Linux
`bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Full audit: `not_equivalent`
(exit 1), while selected gates pass.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-submit-device-20261116/`.
Canonical `bundle/` and full archive restoration pass the unchanged complete
typed inventory checker. Initial successful tests with an already-signaled prior
output fence are diagnostic, with source/binary/log retained; final async evidence
uses an independent pending output fence. `completion.txt` binds twelve source
paths and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `b84035d6b95464688fdc18460852edcfa8fa675acff27e346483fe4007350a52` |
| `bundle.tar.gz` | `990de975d4391cea84f70a9a1ad542015228fb729df3fddc39974e3d392b9355` |
| `bundle/vinix-aarch64` | `9fe61c2c729acb75a9e0510447b844d32f674328c45e43f5c730212c5a8478fe` |
| `bundle/vinix-x86_64` | `16ad29aedfdae7f53d697a5c9c5b359c02dd4bf728ad6e444c163ac9923a3bdd` |

Host services inject GPU work and lock scheduling. Existing state writers,
native visibility, later loss races, heap rates and hardware behavior remain
unqualified. ABI/Mesa, retained queues, reservation fences, memory accounting,
cumulative timelines, fence containers and reclamation remain open. The fake
backend is unchanged. No GPU execution, native hardware test, Vinix/QEMU boot,
reboot, SSH or deployment occurred.
