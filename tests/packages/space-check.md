# Filesystem allocation units in package space checks

Package space preflight now multiplies `statvfs.f_bavail` by `f_frsize`, the unit
used by the filesystem's block counts. The previous calculation used `f_bsize`,
the preferred I/O size, and could overestimate or underestimate available bytes
when those sizes differed. A zero allocation unit or overflowing product fails
with a path-specific diagnostic before acquisition/publication. Transaction,
mirror, catalog, composition and release checks share this production function.

The maintained V [controller](space-check.v) includes the actual platform's
`statvfs` header, then redirects only function calls to a V fixture. Struct
layout and native count widths remain those of the host libc. It invokes the
production `pkgcore.free_bytes` and `disk_check`; the package service receives no
test hooks. The first bounded example reproduces the previous unsafe admission:

| Available blocks | I/O bytes | Allocation bytes | Correct bytes | Previous bytes |
| ---: | ---: | ---: | ---: | ---: |
| 3 | 65,536 | 4,096 | 12,288 | 196,608 |
| 3 | 4,096 | 65,536 | 196,608 | 12,288 |

The first case must refuse a 16 KiB requirement. The reverse case must accept a
128 KiB requirement. Further cases cover equal units, an unused zero I/O size, one-byte units, the native
maximum count, an exactly representable u64 maximum product, zero availability,
invalid zero units, product overflow and a failed syscall. Darwin's native
`fsblkcnt_t` is narrower than Linux's; the fixture derives its maximum from the
native typedef's size. Initial fixture attempts assumed a 64-bit count and are
retained separately from the final results.

```sh
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache run tests/packages/space-check.v
V=/path/to/v V_MACOS_V3_NO_FALLBACK=1 /path/to/v -nocache run tests/packages/space-check.v --sanitize
```

The [distribution driver](distribution-check.v) runs the same normal fixture;
the standalone controller needs no desktop assets. Native lifecycle assertions
and the full signed CLI workflow also exercise real host filesystem reports. Sanitizers disable leak
detection; these checks do not measure whole-service heap retention. Both static
target stages validate the field binding and service builds, without claiming
guest execution or power-cut durability. Concurrent writes, quotas, metadata
growth and filesystem allocation behavior can still exhaust storage after
preflight; existing transaction verification and activation boundaries remain
necessary. Public publisher enrollment, catalog migration and graphical/runtime
acceptance remain separate roadmap gates.

Seven native core suites, the complete signed CLI lifecycle, final normal/sanitized production-call fixtures, maintained driver typecheck and both static target stages passed. Initial fixture calibration and the local test-selection error are retained separately; compiler notices and generated-C warnings remain in private build logs.

- [Host, CLI and target results](results/2026-10-14/space-host.txt).
- [Baseline and initial attempts](results/2026-10-14/space-baseline.txt), [final sanitizers](results/2026-10-14/space-asan.txt).
- [Source/compiler/artifact ledger](results/2026-10-14/space-toolchain.json).
