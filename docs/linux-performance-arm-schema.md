# Explicit ARM slab observation profile

The performance observer now has two compile-time profiles. The default retains
the original 4 KiB pages, fourteen ordered classes and
`vinix-slab-14-4k-v1` protocol. `-d perf_slab16k` selects 16 KiB pages, eighteen
ordered classes and `vinix-slab-18-16k-v1`. The four additional classes are
2688, 4048, 5392 and 8096 bytes, matching the current compact slab header and
`init_medium_slabs` calculation. Other medium-class layouts are refused.
The maintained producer selects this flag for AArch64; x86-64 keeps the default.
Consumers use the same explicit flag rather than guessing a schema from data.

Both profiles use fixed raw storage and fixed class arrays. Header/row identity,
ordering, canonical counters, complete EOF, signed arithmetic and overflow
checks remain required. Large allocation deltas use the selected page size;
object bytes do not double-count slab backing pages. The sampler checks the
actual runtime page size before measuring. The original observation/qualification
distinction remains: diagnostic records preserve nonzero counters, while
qualification requires zero changes in every object/backing-page/large-page
counter and zero writes-after-free at both endpoints.

The full transcript consumer still requires all 44 measurements, DONE, forty
cohorts and eighty raw snapshots. It requires 640 canonical delta rows for the
fourteen-class profile and 800 for the eighteen-class profile. Both strict and
diagnostic readers include every medium class. Exact page sums remain decimal
strings even when the sum exceeds u64. Historical bundles and their original
checkers remain unchanged; default consumers continue to reject eighteen-class
records.

The public host suite passes both schemas in normal and production builds:

| Profile | Parser/reader controls | Strict transcript controls | Diagnostic controls |
| --- | --- | --- | --- |
| 4 KiB / 14 classes | 373 | 57 | 33 |
| 16 KiB / 18 classes | 479 | 72 | 33 |

Additional controls cover each medium class's object and backing-page growth,
missing/duplicated rows, older size identities, missing delta rows, foreign
schema tags and wrong runtime page sizes. The byte oracle for a one-unit
increase in every object and large-page counter is 43,712 for ARM. The public
gate generates intentional host fixtures, checks each with its own consumer and
requires the opposite consumer to refuse it in both build modes. The existing
100-PTY-owner flat-descriptor guard also passes. Native ARM console output
contains two terminal carriage returns. Only the ARM profile admits this
bounded line ending; the default retains LF/CRLF admission. Both profiles refuse
embedded control bytes and three terminal carriage returns, with explicit
complete-transcript controls and native log corruption checks.

Both complete samplers and native reader probes link with strict format and
pointer diagnostics, using the previously verified compiler
`53debcfe66952ba952d64b2b94dbb2408bed6992453d1ac6bad5889e4bd1ec7e`.
Generated C keeps sampler snapshots/deltas and parser cursors automatic. Native
probe buffers use explicit stack storage, with no reader retaining a pointer
beyond its synchronous call. Legacy C probe bytes and workload counts/waits
are unchanged. The current compiler's separate precision issue remains recorded
in the [sampler build report](linux-performance-sampler-builds.md).

Fresh native PID1 probes run against the previously qualified isolated kernels
at `vx-ec-1115/fixed-build-{arm,x86}`. After touching both snapshots, warming
64 reads, waiting thirteen seconds, measuring 200 reads and waiting another
thirteen seconds, every object and backing-page count stays flat: all eighteen
ARM classes and all fourteen x86 classes. Large pages stay 75/75 and 207/207
respectively, with both writes-after-free counters zero. The native log checkers
pass 52 ARM / 44 x86 negative controls. Kernel/probe hashes, fresh process
receipts, serial logs and complete generated C remain in the bundle.

Source baseline is `a3d68ae67bb8f1fff788c919c46ca2bfbead222a`, plus the exact
captured sources. No kernel implementation or lifetime changes are introduced.
This qualifies schema handling and repeated reader cleanup; full ops/churn/cache
and idle/apps/drag performance, other ARM allocator layouts, the selected cached
x86 runtime's missing curl and inherited allocation allowances remain open.
Broader section 15 application acceptance is unchanged.

Complete evidence: `/Users/alex/.cache/vx-p16-1115/bundle`, archived at
`/Users/alex/.cache/vx-p16-1115.tar.gz`, SHA-256
`28fcc72c4cd74371040e3d00730ac6938ed75872433454739d796133ded14246`.
The maintained archive checker decodes every member and compares all bytes,
paths, types, modes and literal links with the retained bundle. Originals remain
intact.
