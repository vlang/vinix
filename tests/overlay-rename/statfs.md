# Allocation-free filesystem space measurements

The opacity storage-failure test exposed a separate leak in `statfs` and
`fstatfs`: the resource dispatcher allocated an unfreed 16-byte interface
wrapper on each call. The four small objects recorded by the earlier
[opacity qualification](opacity.md) came from its four space measurements.

The dispatcher now initializes a borrowed capability inside a concrete holder
allocated in the caller's stack frame. This avoids both narrowed-interface
boxing and promotion of an address-taken V local when returning a composite
value. All seven supported backends return synchronous numeric values and
retain no receiver pointer. Source and generated-C review on both architectures
confirm no wrapper allocation, receiver promotion or new lifetime issue.
Filesystem values, lookup, descriptor validation and authorization remain
governed by the existing syscall paths.

Run the [V controller](README.md) with `--case opaque-full`, a matching isolated
kernel and a fresh state directory. Before the storage failures, UID/GID 1000
opens the private volume and performs 1,000 pathname and 1,000 descriptor calls.
Every result must report the same ext2 type, block size and free block/inode
counts. The host controller independently compares every live slab class and
the large-allocation count before/after the calls; growth fails the run even
when all guest functional assertions print `PASS`. The ordinary repeated
`ENOSPC` rollback/recovery/remount checks still follow.

## Evidence from 13 October 2026

Inputs and results are retained in `build/development17-20261013`:

| Run | Result |
| --- | --- |
| `statfs-arm-before-a`, `statfs-x86-before-a` | Saved opacity kernels pass metadata/storage assertions but retain exactly 2,000 size-16 objects after 2,000 calls. The host memory gate rejects both. |
| `statfs-arm-after-a`, `statfs-x86-after-a` | All live classes and large counts stay flat across 2,000 calls, and across the later repeated storage failures. Exact block/inode rollback, rename refusal, recovery and remount pass; read-only `e2fsck` clean. |
| `statfs-arm-all-a`, `statfs-x86-all-a` | All concurrent rename, backend refusal, whiteout, directory-opacity, work invalidation and recreation cases pass; read-only `e2fsck` clean. |
| `statfs-arm-http-a`, `statfs-x86-http-b` | Authenticated HTTP/account/job/build gates pass, with 19 independently validated records each. |

The pre-fix AArch64 allocation-tracked run
`opacity-arm-failure-tracked-c-sites-named.log` names the four measurement
allocations as `resource__filesystem_stat <- fs__fill_statfs_resource <-
fs__syscall_statfs`. Its tracker reports zero dropped records. The preserved
production controls and final runs use identical fixture inputs.

| Input | SHA-256 |
| --- | --- |
| Before ARM kernel | `74ca0751a29da0345bf3ce233dec8ee496ea22c1372d1af0cc5bc32a0dd8604d` |
| Before x86 kernel | `0e0121db04e49007221780c65457ae54feac8baba9e1209b05a76cfecfceaf07` |
| Final ARM kernel | `855b421cb8120bf55d97ad726feb1ff22de4945992fa3898e55b8b6128791b9b` |
| Final x86 kernel | `8a2559e0365a398f7eac77d6823e699c2884896d06c3d3824d4cc7449f5d2654` |
| Storage-full fixture | `46c7d4718568f4da2fd877d1ba98ed0293102fab667defca5940dc6af3d0224a` |
| Statfs fixture | `abdcc48785c62324a1b573fa98b534dada1f6fe7ee634c7473ed34a352211a91` |

The isolated kernels retain the earlier `9b01dbca2` baseline and filesystem
patches, including `8fc078a86` and `2eedad39b`, plus this dispatcher correction.
They use the preserved `compiler-f6358ec/v-from-bootstrap` compiler and
link-shuffle seed 17. `statfs-lifetime-review.md` records independent approval.
`statfs-evidence-checked.log` verifies generated C, immutable/copy hashes,
pre-fix growth, final slab equality, filesystem checks and native receipt counts.
The allocation allowlist audit still has exactly the same 182 baseline file/kind
failures as the opacity audit. Its allowlist was not expanded.

The initial x86 HTTP gate timed out while reading GET `/index.html` in its
second workspace. Its failed receipt remains in `statfs-x86-http-a`; the fresh
`statfs-x86-http-b` run is the passing qualification. Source/generated-C review
rejected the first two dispatcher proposals because V still allocated wrappers.
Neither was used for final guest qualification.

Evidence checkers are compiled without `-prod`, and a deliberate failed-assert
control verifies a nonzero exit. The host compiler's release mode removed
assertions from the initial checkers. All opacity and final statfs records were
rechecked with active assertions; the checked logs supersede those initial
checker outputs. Native guest assertions and the controller's slab gate use
explicit failure paths. Kernel builds continue to use the preserved compiler.

The final ARM kernel completes the full `ops,churn,cache,idle,apps,drag` run in
`statfs-desktop-perf-a`. All 36 batches of 200 syscall operations retain zero
bytes per operation; all four 300-process churn batches retain zero bytes per
run, with no additional live objects or slab pages. The cache workload writes
32 MiB and records 16 MiB cached. Desktop process-count and duration checks
pass. The extracted boot-disk kernel matches the final ARM hash above.
`statfs-desktop-perf-a.json`, `statfs-desktop-shots-a`,
`statfs-desktop-serial.log` and `statfs-perf-evidence-checked.log` retain the
report, screenshots, complete capture and assertion-enabled validation.

This closes the measured filesystem-stat interface leak and makes storage
rollback measurements stop adding their own wrappers. General overlay-node
retention, crash recovery and wider roadmap section 17 acceptance remain open.
