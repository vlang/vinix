# Binary syncobj reset

Offline increment, 2026-11-16. Full M1 equivalence remains **incomplete**; see
[the parity report](m1-agx-parity.md).

Vinix now implements `DRM_IOCTL_SYNCOBJ_RESET`, previously missing from its
generic DRM core. The request uses the Linux 16-byte handle-array layout and
read/write ioctl encoding `0xc01064c4`. Nonzero padding or zero handles returns
`EINVAL`. The handler copies handles once and resolves every object identity
before changing any object. Copy, allocation and lookup errors return
`EFAULT`, `ENOMEM` and `ENOENT`, respectively. Successful effects are sequential
per object, as in Linux; the array is not a globally atomic transaction.

Up to 64 handles use stack storage. Larger requests allocate one checked,
fallible handle/object prefix and free it on every exit. Reset does not need
wait capture nodes. Binary fence replacement also removes previous timeline
lookup membership under the object lock. Old captured fences retain their
identity and completion state; reset does not signal in-flight GPU work.
Pending first-publication captures survive nil replacement and capture the
first later fence. Native object/fence metadata remains retained, and cleared
timeline arrays keep their reusable capacity.

The reference is the packaged
[Linux DRM reset implementation](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/drm_syncobj.c)
and [generic DRM UAPI](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/include/uapi/drm/drm.h).
Source guards now check both and retain the generic header in audit bundles.
Fresh Omarchy `29fbc4e2de4e57525acc6195351e86a31773e158` and packages
`0b63ba1dd64298a2dd38250d25691dbd0975a88b` match the remote heads checked during
this run. The package clone was refreshed after its remote advanced. Their
pins remain Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`; m1n1 is
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Validation passed:

- ASan/UBSan with stack-use-after-return detection: 4,600 reset checks over
  200 cycles, plus 11,400 existing wait checks, 4,103 geometry probes and
  200 capture primitive cycles. Reset cases cover 1..4096 handles,
  duplicate/distinct objects, validation before effects, inline/owned failure
  cleanup, old timeline/fence snapshots, first-publication capture and handle
  destruction/reuse at the object lock. Every allocated owner returns its
  bytes; this measures injected storage lifetimes, not native kernel heap use.
- Asynchronous submission and DRM wire/node sanitizer regressions; three V
  unit suites (fourteen test files); selected source/reference contracts;
  strict generated-C checks for 54 live ARM helpers and negative selftests.
- Isolated ARM and clean x86 kernel builds from
  `356930ebebe045c09cc71404645ed6561f9fef40` plus four retained overlays:
  `kernel/drm/drm.v`, `kernel/drm/wait_storage.v`, `kernel/drm/ioctl/ioctl.v`
  and `kernel/drm/syncobj/syncobj.v`. Both contain generic RESET; x86 excludes
  native AGX. Selected AGX/DRM and reviewed process/scheduler/exit inputs
  match the isolated builds. Each ELF/C/input set was retained before changing
  architecture. The audit records a later shared-checkout HEAD; source hashes
  bind its selected inputs to this isolated baseline and the four overlays.
- Independent source and retained ARM generated-C lifetime review found no
  defect. It checked owner transfer, every error cleanup, prefix bounds,
  absence of hidden allocations, array clearing and old capture retention.

The unchanged global allocation allowance audit **still fails** for this change
and its unchanged baseline. Both complete reports have identical source counts
and per-file/per-kind counts: 385 ARM and 291 x86 V-reported allocation sites.
The original failures and their comparison are retained; neither auditor nor
allowances were changed. This does not certify leak-free native execution.
The final parity audit passes its selected source gates and returns the
expected `not_equivalent` verdict (exit 1).

Evidence is retained outside Git at
`/Users/alex/.local/state/vinix/omarchy-m1-syncobj-reset-20261116/`.
The canonical `bundle/` includes sources/references, test binaries/logs, both
kernels and generated C, review, original allocation reports and the unchanged
complete typed inventory checker. Canonical and fully restored inventories
passed. The initial 4,000-reset-check run remains a diagnostic alongside the
expanded final run. `completion.txt` binds eighteen non-report paths and two
reports to the feature commit and sealed evidence.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `f7e94a4a6f5888045fb1e813cad7846e366ff876ad2342357c199f5b0d967cb5` |
| `bundle.tar.gz` | `1686dc25000a31e22e8782cbe169794b3ba91c549bf0b8571b787dbcee044266` |
| `bundle/vinix-aarch64` | `439bd6728b6f90736808374cd14b4916b8c16d74ca7fa731aa8355b6aa8bb02c` |
| `bundle/vinix-x86_64` | `f9e3b80e078cae52a07c7a1c85497b11f21c609ddda0ed6694acc66a5ea6d0e2` |

Modern ABI/Mesa integration, full Linux timeline/reservation semantics,
remaining generic syncobj operations, namespace capacity, polling versus
sleeping callbacks, cache policy and accounting remain open. No Vinix boot,
GPU/firmware execution, native heap measurement, actual multi-CPU race,
hardware test, reboot or deployment was performed.
