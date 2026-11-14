# Select timeout clock bounds

The timeout fixture now accepts a remainder equal to the requested duration
when the kernel's start and finish clock samples coincide. It still requires
canonical output, a remainder no greater than the input duration, and a lower
bound derived from the enclosing user-space clock samples. Timeval output
allows at most 999 ns of truncation. Negative, increased, noncanonical and
out-of-bound values are rejected before arithmetic can overflow.

This follows [Linux v6.12's select deadline and remaining-time calculation](https://github.com/torvalds/linux/blob/v6.12/fs/select.c#L275).
The previous strict-decrease condition could reject a valid fast syscall.
Production kernel code is unchanged.

## Failure and diagnosis

The [ppoll argument qualification](linux-ppoll-arguments.md) retained variable
x86-64 selecttimeout failures: raw select returned EINVAL for a negative count
and left exactly 500,000 microseconds. The original fixture required less.
Both baseline kernels reproduced that refusal with the same diagnostic ELF.

A qualification-only x86-64 kernel records the deadline, finish-time sample
and computed remainder before printing. Its isolated worktree starts at
`c5e88c2f34706c95601407e01864dac8f060403f`; the retained
`selecttimeout-trace.v` generator instruments only the timeout finish helper
and adds a bounded trace counter. The trace reuses the same clock/subtraction
operations, with no new allocation or production change.

The unchanged diagnostic ELF produces 32 captured records. Each remainder
equals deadline minus finish time. Records include:

```text
deadline=1/184839000 now=0/684839000 left=0/500000000
deadline=1/323631000 now=0/823631000 left=0/500000000
```

Subtracting the requested 500,000,000 ns from either deadline gives exactly
its finish-time sample. These are coincident samples, so strict decrease is
not a valid requirement. Trace output can interrupt buffered guest case lines;
the trace establishes the clock observation, while separate uninstrumented
boots supply semantic and cleanup results. Earlier refusals and their strict
historical audits remain preserved.

## Fixture correction and qualification

Fast raw x86-64 select readiness, EBADF, negative-count EINVAL and bitmap EFAULT
cases now start with `tv_sec=0, tv_usec=1500000`. Valid canonical writeback is
observable even if no time elapses: leaving the input untouched still fails.
Read-only and libc pselect inputs must remain unchanged. Existing expiry,
signal delivery, handler-visible writeback, saturation, exact errno, descriptor
guards, queued data and restored-mask checks remain in place.

The shared allocation-free bounds helper passes ten positive and sixteen
negative controls, including coincident samples, normalization, truncation,
expired durations and signed limits. The registered runner freezes all three
fixture sources. Newly compiled static musl ELFs run unchanged on Linux
6.12.51 and the retained production Vinix kernels:

| Architecture | Timeout checks | Vinix failures | Linux failures | Registered cases |
| --- | ---: | ---: | ---: | ---: |
| AArch64 | 1,536 | 0 | 0 | 4/4 |
| x86-64 | 2,208 | 0 | 0 | 4/4 |

Registered cases are selecttimeout, ppollargs, maskwait and selectfds. Both
credential cohorts warm 64 full timeout-matrix cycles and measure 200 cycles.
Every live slab class stays flat, allocator taint stays 0/0, and large pages
remain 89/89 on AArch64 and 222/222 on x86-64. Linux explicitly skips Vinix
storage measurements.

Production kernels are byte-identical to the ppoll qualification's fixed
kernels, built from `9fe8e86079f056dcf3ff0b39d6969016bd4df1cf` plus its retained
file.v patch with V 0.5.2 `7d74206`, `PROD=true LIMINE_MP=1 ALLOC_TRACK=0` and
link seed 42. No production rebuild is claimed for this fixture correction.
Generated fixture C changes only the probe inputs/bounds and adds the pure
helper after canonicalizing absolute-path hashes in two ignored storage-loop
variable names. Its stack allocations and all other generated code remain unchanged.
Independent bounds/lifetime review passes. Historical checker sources remain
unchanged.

## Evidence and reproduction

Run `run.v --cases selecttimeout,ppollargs,maskwait,selectfds` with either
retained production kernel and a fresh external state directory.
`selecttimeout-reference.v` runs the identical probe ELF on Linux.
`selecttimeout-bounds-check.v V-COMPILER FRESH-STATE` compiles the exact pure
helper and its positive/negative controls.

Build `selecttimeout-bounds-evidence.v` without `-prod`, using
`-cc cc -cflags -O2`. Its two arguments are the new bundle and the complete
historical ppoll bundle. It audits both inventories, invokes the frozen
historical auditor, checks sampled clock arithmetic, controls, reviewed source
identities, generated-C scope, identical production kernels and native/Linux
ELFs, frozen fixture inputs, strict semantic output and flat cleanup.

The new external bundle is `/Users/alex/.cache/vx-tb-1114/bundle`; its
514-file manifest has SHA-256
`7ff73f79788b3f14f3f938a4c0f02475e3c7c8651376fffa908658a009e9c225`.
The required historical bundle is `/Users/alex/.cache/vx-pa-1114/bundle`;
its 639-file manifest remains
`fa21bda6d3f7af40d1e35821ca144215c46a2a1edde7ae1e1dd962d6a994420d`.
Neither historical evidence nor its refusal conditions are replaced.

This closes the variable timeout-fixture regression recorded in the ppoll
report. Broader §15 semantics, application installation/integration and
translated-runtime acceptance gates remain open.
