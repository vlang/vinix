# Native AGX error publication

AGX command errors and aggregate submission failures now use explicit `i64`
storage. Native V `int` fields lower to 64-bit C slots in this toolchain, while
the ARM atomic specialization for `int` selects 32-bit loads/stores. A narrow
store leaves high bits stale; a narrow unsigned load can turn a negative errno
into a large positive value. On a zeroed slot, `-5` could become `4294967291`.

The two explicit-width fields select the existing 64-bit atomic routines.
Conversions at API boundaries preserve the signed errno. Pending C struct
declarations remain identical, and callback, cancellation and ownership order
remain unchanged. Kernel-wide `int` atomic handling remains open.

Packaged Asahi maps
[work failures](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs)
to kernel errors, including timeout, I/O and device loss, and publishes them
through its [completion callbacks](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/queue/render.rs).
The Vinix fence path must retain their negative signed values.

Validation passed offline:

- A new ARM macOS probe compiles the actual pending-error reader, callback
  publisher, field declarations and production `katomic_arm64.v`. It executes
  the production ARM load/store instruction bodies on host memory. Only host
  symbol spelling and ELF type directives are adapted for the assembly object;
  callback disposal is stubbed to isolate error publication. ASan/UBSan passes
  seven negative errnos, poisoned high words, neighboring completion visibility
  and aggregate-error overrides. Existing full async fixtures separately cover
  actual disposal and lifetime behavior.
- The original baseline file/pending/atomic sources are checked against their
  Git blobs and compile into a probe that fails the error-storage assertion.
  Three additional complete source variants compile and fail designated load,
  store or override assertions. All four retain their binaries, generated C,
  assembly and complete fixture inputs externally. Committed V runners recreate
  the probes; generated artifacts stay outside Git.
- Generated-C guards require all six affected kernel callers and both probe
  callers to use full-width error operations, then check the actual `i64`
  atomic implementation's instruction selection. Four width mutations are
  rejected for each output. Both pending C structs match the baseline exactly.
  All six changed function bodies reduce exactly after restoring the old atomic
  helper names and removing only explicit identity casts on error values.
- Fresh isolated ARM/x86 builds pass. Nine native preparation, cleanup,
  retirement and publication bodies, file close, queue capture/release,
  timestamp reaping, callback disposal, per-command capture retirement and both
  GPU completion bodies match baseline after resolving generated string IDs.
  Both source overlays match both build snapshots; x86 C matches after
  normalizing compiler discard-variable path hashes.
- All 52 focused V test files, 145 historical native storage guards and their
  three selftests pass. Six timestamp/staging helper guards pass on host/native
  C with 18 allocation mutations each. Wait, wire, fence, close, full async,
  CPU-cache, VM, sanitized TLB, layout, render and packet-reader fixtures pass.
  Fresh source-derived fixtures pass 12,000 work images, 14,400 timestamp images,
  48,000 microsequence images, 30,375 tiling results, 16,384 packet commands and
  24,576 resolved-destination images. Per-command and blocked timestamp retirement
  tests remain enabled in the full async fixture.

Allocation audits are unchanged at 381 ARM / 289 x86 sites and 833 / 813 source
files, including the existing allowance-check failure. Native heap rates remain
unmeasured. This fix adds no allocation, free or owner transfer.

Fresh heads: Omarchy `dceae1857bc5df80eedbba07ff8a03c2dc428fdd`, packages
`6db3e0d69a75a8a8bb644e4e3643c9d0f3243b3c`. Selected Linux/Mesa/M1 package
definitions are unchanged. Pins remain Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
Mesa `b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`, m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. The full audit remains
**not_equivalent**. Modern UAPI/Mesa integration, render-stage ownership,
timestamp publication/units, manager/UAT replacement, firmware teardown,
reservation fences, timelines, remaining wire/default coverage, topology and
power/reset behavior remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-native-errors-20261116/`.
Baseline is `71ea9ac50ef3ebdf81ac015fee709275f70b7a18` plus six retained source
paths, including two native overlays. Ten unchanged independent runner binaries
are reused after source/binary checksum checks; dependent model and native-error
probes are fresh. The unchanged typed inventory checker verifies the preceding
complete bundle, this complete bundle and a full archive restoration.
`completion.txt` binds sources and reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `ffea5bd3122c1818ec7afbc8a652ae880297f9f7ce6fecdc7101c2ce87a89e0d` |
| `bundle.tar.gz` | `2b6170e38f89c9449f3dfcc7da4041ef3886bd8933452f89cc95a56a80cf750a` |
| `bundle/vinix-aarch64` | `a7c1893ccb7d1a21b927159122ec2ca9caebb78fa3d88b1af1cb5306025afdb4` |
| `bundle/vinix-x86_64` | `1cf8255e964c69336186a2f735980193d11c2bdc77586b280d30804c557d77ec` |
| `bundle/blob-aarch64.c` | `448274a02cd6d46da01f84a40edcc81a6c5c6bc9c2666f1925355f8f8826362b` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
