# Timestamp capture ownership

Vinix now resolves modern timestamp handle/offset pairs into captured firmware
addresses while retaining their mapping owners. UNBIND hides captured names
without unmapping their storage. Capture references also keep the file alive
before a submission acquires its VM pin. The public Mesa 25 submission path
remains unchanged; modern capture is still an unregistered migration component.

The reference is packaged Asahi's
[common lookup helper](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/common.rs)
and [timestamp ownership](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/timestamp.rs).
The helper clones an object reference under the namespace lock, releases that
lock, validates the offset and retains the firmware mapping. UNBIND removes
only the namespace's reference; captured commands remain owners.

Vinix uses reference counts on its per-file value entries and returns scalar
IDs/addresses, so array movement cannot invalidate a capture. Detached entries
keep their IDs reserved until final cleanup. Lookup ignores the offset for a
null handle, returns ENOENT for missing/detached/foreign names before checking
their offsets, rejects u32 offset-plus-eight overflow with EINVAL and reports
out-of-range destinations with ERANGE. Byte offsets need no alignment.

The six engine/phase slots retain duplicate destinations independently. A
failed lookup releases the acquired prefix and clears output; an already owned
output cannot be overwritten. Final release retries detached cleanup under the
file lock. Missing managers retain mapping/GEM ownership for the worker to retry.
File close refuses live captures and mapped timestamp owners without a manager.
The global timestamp allocator's native map/unmap operations now take the GPU
manager lock, serializing allocations and physical cleanup across files.

The future modern submit path must retain these captures through actual job
retirement and release them outside `GpuManager.lock`. Its current GPU
completion callbacks hold that lock; release belongs in file-worker retirement.
Timestamp result publication/unit conversion, original mapping ownership across
manager/UAT replacement and firmware/cache/TLB-safe teardown remain separate
integration requirements. This increment does not certify those behaviors.

Validation passed:

- ASan/UBSan fixtures run 2,176 lookup/range/overflow cases and 64 complete
  retained-mapping lifecycles. They cover duplicate destinations, unaligned byte
  addresses, namespace growth, detached-ID reservation, absent names, capture
  before VM pin, UNBIND, close refusal, live-capture worker retries, missing
  manager retention and eventual cleanup. All six failure positions roll back;
  deterministic UNBIND between the first and second lookup releases exactly
  the retained prefix once. Every fixture GEM owner is released at completion.
- An extraction fixture executes the actual native timestamp map/unmap bodies
  with injected allocator/UAT services. One hundred cycles check lock balance
  on malformed input, absent UAT, allocator/map failure, rollback and success.
- Fifteen complete native-source mutations compile and fail their designated
  ownership, validation, rollback, retry or locking assertion. The runner and
  fixtures remain in Git; full sources, executables and failures are retained
  outside Git. Stack-use-after-return detection is enabled.
- All 50 focused V test files and selected reference gates pass. The 142 native
  C storage guards, six host capture guards, twelve packet/parser guards and
  all three allocation-mutation selftests pass. Generated-C review confirms
  unchanged legacy staging, native job preparation/retirement/publication,
  queue/VM reapers, queue capture, callbacks and worker service. Close adds only
  retention gates before its existing cleanup; free/GEM-drop site counts remain
  unchanged. Registry service adds only timestamp retry. Capture helpers have
  no temporary allocations; production eliminates their unregistered entries.
- Fresh isolated ARM/x86 builds pass, with all three native overlays retained.
  x86 C matches the previous checkpoint after normalizing compiler
  discard-variable path hashes. Wait, wire, fence, close, async, CPU-cache, VM,
  sanitized TLB, layout, render and packet-reader regressions pass. Fresh
  source-derived fixtures pass 30,375 tiling results, 12,000 work images, 14,400
  timestamp images, 48,000 start/finalize images and 16,384 packet commands.
  Independent lifetime review found no component blocker and identified the
  integration requirements above.

Baseline and feature allocation audits still fail the unchanged allowance at
381 ARM / 289 x86 sites. Per-file/per-kind counts match. ARM source count grows
from 831 to 832; x86 remains 813. Native heap rates remain unmeasured.

Fresh heads are Omarchy `e19607fc5ab3cbe6d2d4ebb13bd9e990db3854d1` and packages
`236f007a15a79f0b56026e019349f425e44db022`. The selected package definitions are
unchanged. Pins remain Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The fresh full audit still reports
**not_equivalent** (exit 1). Modern ABI/Mesa integration, capture/job transfer,
timestamp publication, reservation fences, cumulative timelines, VM capacity,
remaining wire/default coverage, topology and power/reset gaps remain.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-timestamp-capture-20261116/`.
Baseline is `10386247b5475341741e7f4481cb3498f5c067cd` plus sixteen retained
source paths, including three native overlays. Nine unchanged independent
runner binaries are reused after source/binary checksum checks; dependent
fixtures are fresh. The complete prior bundle, current canonical bundle and
full archive restoration pass the unchanged typed inventory checker.
Seven selected Asahi files are retained after comparison with their Git blobs,
including the common lookup helper and timestamp ownership implementation.
`completion.txt` binds the sixteen sources and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `fa030716b706451546dde2343a1f03425a6632ef1a4abfd7e04218239c7b76bd` |
| `bundle.tar.gz` | `dffa37a5342d0c17743d89b17fe02937b991c9fd3a944871c90bc8d7fd455a71` |
| `bundle/vinix-aarch64` | `a7aabb789f911e1f86beee4a8405e3055417dc6e37d22703b535927c33cf926c` |
| `bundle/vinix-x86_64` | `2fa4ec5aba2f5a53370b17c6c591da1bada5ae5280430a18dae0f64f89bf1e03` |
| `bundle/blob-aarch64.c` | `8f0a0cb699a0210819ced517db2ed53f11844b5b3f849cd2f73a1bbc56145389` |

No GPU workload, hardware test, Vinix/QEMU boot, reboot, SSH or deployment occurred.
