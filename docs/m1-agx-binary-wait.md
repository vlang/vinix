# Binary syncobj wait snapshots

Offline increment, 2026-11-16. Full M1 parity remains **incomplete**; see
[the parity report](m1-agx-parity.md).

Vinix previously reread user handles and the current syncobj fence while
waiting. Replacing that fence could redirect an existing wait, hide an earlier
completion or satisfy the wait with unrelated later work. The packaged Linux
DRM core copies handles, retains object references and waits on captured fences.

The native binary wait handler now copies handles once, resolves every object
and snapshots existing fences under each object's lock before checking
readiness. A later replacement or handle destroy/reuse cannot redirect a
captured wait. An empty object requires `WAIT_FOR_SUBMIT`; only empty snapshots
are polled again, and every pending iteration yields to the scheduler. Default
syncobj creation now starts empty; signaled creation installs a completed fence.

Binary waits reject timeline-only `WAIT_AVAILABLE`, accept empty arrays,
distinguish missing handles (`ENOENT`) from copy faults (`EFAULT`), and retain
`EINVAL` for an empty object without `WAIT_FOR_SUBMIT`. Like Linux's binary
handler, the unused padding word is ignored. `WAIT_ANY` reports a ready index;
`WAIT_ALL` requires every captured fence, including failed fences, to complete.
Readiness is checked before absolute timeout expiry.

No new owning allocation, free or callback registration/lifetime is introduced.
Non-owning snapshots stay in fixed stack arrays during the synchronous ioctl;
native object/fence metadata retention is unchanged. Generated-C checks enforce
those stack arrays and reject temporary allocations.

Validation passed:

- ASan/UBSan executed the production create/wait handlers, complete syncobj
  module and request definitions. There were 3,600 recorded checks across 200
  cycles, plus direct pointer, count, copy-fault and namespace checks. Scripted
  scheduler steps covered replacement with pending/completed fences, capture
  from an empty object, destroy/reuse, mutable user handles, `WAIT_ANY/ALL`,
  absolute timeouts, flags and errors. Fixture-only cleanup follows all callers
  and scripted actions. Locks, atomics, time and user copies are injected.
- Production asynchronous ioctl/pending submission and DRM node/request-copy
  sanitizer regressions passed.
- Three V unit suites (eleven test files), selected source/reference gates and
  strict generated-C storage checks for 44 live ARM helpers passed. Negative
  checker selftests passed. The audit now checks and retains packaged
  `drivers/gpu/drm/drm_syncobj.c`; its overall result remains `not_equivalent`
  (expected exit 1).
- Isolated ARM and clean x86 kernel builds passed from
  `098b10d9a65591ba882680ffe762ff9093ce6e63` plus one retained
  `kernel/drm/drm.v` overlay. Selected AGX, syncobj, GEM and ioctl V files plus
  `drm.v` matched the audited checkout. Both generated C outputs include the
  changed generic wait handler; x86 excludes AGX. The first x86 link selected
  macOS's linker and failed on ELF options. The existing
  `LD_X86_64=ld.lld` option successfully linked the cleanly compiled objects;
  both attempts are preserved.

Fresh checkouts matched remote Omarchy
`9f68da882545cf4aae8a6c15cce06fada0f116dd` and packages
`3c4bee48824403de535a61f5648eefd009352602`. They still select Linux-Aurora
`bed544bdf93a496ebf70ba180923bab12b6e01cf` and Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`. The m1n1 reference remains
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

Evidence is retained outside Git at
`/Users/alex/.local/state/vinix/omarchy-m1-binary-wait-20261116/`.
The canonical `bundle/` includes source/reference snapshots, logs, native
sanitizer executables, both ELF kernels and generated C, provenance and the
unchanged complete typed inventory checker. The original inventory and a full
archive extraction both passed verification. `completion.txt` binds the
feature commit's 13 non-report source paths and two reports to that evidence.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `62f3345bd684b7a24023abcaf65266619dee97e67365ce6a00f140254b7d8564` |
| `bundle.tar.gz` | `cf2ac81d00884d2549bf85f804a6db8665a794a54329b98101e8015e8aa34496` |
| `bundle/vinix-aarch64` | `128d159b769a6da4fe6ffca7dafb04ca3b8e7391916d2a1cccb5c4d8972eea8d` |
| `bundle/vinix-x86_64` | `38cc521fd49b66a611b3f72c5eaa05ccf15ea06c4034de7166357df0baa7566e` |

This is not complete Linux wait equivalence. Vinix still limits a wait to 64
handles and uses scheduler polling instead of interruptible callback waits.
An empty object's fence can be replaced between polls before being captured.
Scheduling deadline hints, timeline chains and reservation semantics remain
open, alongside modern ABI/Mesa integration, cache policy and accounting.
No kernel heap measurement, actual multi-CPU race, GPU/firmware execution,
Vinix boot, hardware test, reboot or deployment was performed.
