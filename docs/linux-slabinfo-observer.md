# Native slab-statistics reporting

`/proc/slabinfo` now samples the ordinary allocator into caller-stack storage
and formats directly into the synchronous read buffer. The old path allocated
a Text buffer, a class array and a returned string while observing the heap.
The class array alone appeared in the counters it reported. Those allocations
are absent from the complete generated-C formatter/sampler scope on both
production architectures.

`heap_classes_into` is available in ordinary builds as well as opt-in lifetime
tests. It retains its XNU zone refusal; procfs explicitly returns `EOPNOTSUPP`
for that backend rather than presenting ordinary-slab counters as zone usage.
Insufficient class storage returns an error before report output. The current
eighteen-slot bound covers both native class registries.

The streaming writer uses separate skip and remaining counters, avoiding
offset-plus-count overflow. A fixed twenty-byte decimal scratch handles every
u64. Caller-frame class/writer storage and borrowed output pointers survive
only the synchronous read. No new heap object, ownership transfer, deferred
free or shortened resource lifetime is introduced. The independent review
covers both final kernel translations and both final native fixture builds.

The text layout and ordinary read permissions remain unchanged. Each read
regenerates its report, and each class/shard retains its own lock: there is no
atomic whole-heap snapshot or per-open saved report. Descriptor lookup/open,
positioned-I/O bounce buffers and other syscall work can still allocate.
Different positioned read sizes can consequently expose different numeric
snapshots, even when the formatter itself allocates nothing.

## Focused qualification

The baseline kernel source is `80087c58b5e18f25a755b9db2d662901df80c9a3`.
Separate sparse Git worktrees contain that revision and the three-file feature
overlay, with this checkout's untracked kernel dependencies linked explicitly.
Both kernels build for AArch64 and x86-64 with `PROD=true`, `ALLOC_TRACK=1`,
`LIMINE_MP=1` and section-layout seed 42. Build input maps, commands, generated
C and final ELF hashes are retained. Installed host/SDK dependencies are not
claimed hermetic.

The production formatter passes 156,208 explicit host checks in both normal
and production builds. They cover all offsets through EOF, zero/small/large
counts, both registry sizes, full-width decimal boundaries, null zero-output
and huge-offset reads, and unchanged prefix/suffix guards. Expected bytes use
an independent host formatter. All thirteen generated-C functions pass the
allocation-scope checker and thirteen injected-allocation refusals per target.

The same final native probe per architecture passes on the matching baseline
and changed kernels. As root and UID1000, it checks complete reports assembled
with requested sizes 1, 2, 7, 19, 31, 127 and 4096, guarded output, zero reads
and high signed64 EOF. The complete requested output range, including the EOF
probe, fits its guarded buffer. Both 200-read cohorts retain every live-object,
backing-page and large-page counter flat, with zero written-after-free counters.
These are compatibility and cleanup controls, not a claim of an old semantic
failure or of universal allocation-free syscalls.

The first fixture incorrectly compared numeric reports across differently
sized positioned reads. It failed on both kernels because those syscalls own
different bounce buffers; those failed runs remain retained. Final tests check
the complete native schema and guards separately from exact host byte ranges.
An independent review also required widening the fixture output allocation to
cover its entire requested EOF range. The final guarded builds and guest runs
include that correction.

Both global allocation-policy runs still refuse the same existing allowance
groups. Each reports 385 ARM and 291 x86 allocation sites; the new formatter
has no reported sites. No allowances or historical checkers were relaxed.

## Cold-reader observations and full workload

The unchanged placement ELF and complete checker run against both kernels.
They retain the original two-CPU warmup, measured-read counts, grace waits and
affinity restoration, and explicitly report `qualification=false`.

| Architecture | Baseline cold pair | Changed cold pair | All warmed pairs |
| --- | --- | --- | --- |
| AArch64 | Class 512, 15 to 16 pages | Class 1536, 2 to 3 pages | Flat on both kernels |
| x86-64 | Class 512, 72 to 73 pages; class 1536, 8 to 9 pages | Flat | Flat on both kernels |

Every pair has unchanged object/large-page counts and zero corruption counters.
The changed cold observations contain one fewer live size-512 and one fewer
size-1536 object on both architectures, consistent with removal of reporting
buffers. The surviving ARM page increase shows that formatter removal does
not eliminate all observer effects or explain every earlier workload delta.

The fixed ARM `ops,churn,cache,idle,apps,drag` run completes on the changed
production kernel. Preparation, runtime input verification, resource bounds
and supervisor `ECHILD` cleanup pass. The unchanged observation consumer admits
all 44 measurements, 40 cohorts, 80 snapshots, 720 class pairs and 800 delta
rows; the warm-proof consumer verifies all 40 original reader proofs.
Observation is explicitly nonqualifying. Both unchanged strict consumers
return failure for these four backing-page increases:

| Cohort | Class | Live objects before/after | Pages before/after |
| --- | ---: | ---: | ---: |
| Rename, `/tmp` | 256 | 8709 / 8709 | 142 / 143 |
| Rename, `/tmp` | 512 | 7025 / 7025 | 230 / 231 |
| Rename, `/tmp` | 2048 | 4 / 4 | 1 / 2 |
| `/usr/bin/curl --version` churn | 32 | 1961 / 1961 | 7 / 8 |

All object and large-page deltas and corruption counters are zero. The curl
cohort also measures 16 KiB physical retention over 300 runs; the other three
churn programs report zero. These results do not name the allocation or page
transition responsible, and no allocator or flatness allowance changes here.
No complete x86 performance run is qualified by the focused x86 reader tests.

The 1,081 resource samples have maximum apparent charge 1,652,482 KiB, minimum
free disk 17,995,160 KiB, maximum sample window 1.131 seconds and maximum
sample-start gap 1.152 seconds. The original three-second command limit,
five-second sample bound, disk floors and 4.5 GiB charged-state ceiling remain
in force. The complete raw resource journal and supervisor maxima are retained.

Broader section 15 gates remain open: arbitrary musl/glibc semantics, complete
application installation/update/desktop integration, Linux sandbox/portal and
packaging runtimes, and full native/translated/32-bit workload qualification.
Neither the earlier five rejected page rows nor unrelated acceptance failures
are retroactively qualified by this change.

Reproduction sources are in [tests/procfs-slabinfo](../tests/procfs-slabinfo/README.md).

## Retained evidence

Focused state is retained at
`/Users/alex/.cache/vinix-slabinfo-20261115`, archived as
`/Users/alex/.cache/vinix-slabinfo-20261115.tar.gz` with SHA-256
`693af3f3a5928f3c29a0e0a4b69017fd8a01fe1ae17c4988fb6dd77e21c704f2`.
The complete archive/root comparison passes for all logical file contents,
paths, types, permissions and literal links. Originals remain retained.
The bundle includes final source copies, paired production builds, generated
C, strict native links, all original and corrected fixture runs, host controls,
placement receipts, the complete focused audit and independent lifetime review.
Its dependency receipt rechecks the preceding source-snapshot and placement
archives; those original namespaces and dependency bundles remain required.

Full performance state is retained separately at
`/Users/alex/.cache/vinix-slabinfo-performance-20261115`, archived as
`/Users/alex/.cache/vinix-slabinfo-performance-20261115.tar.gz` with SHA-256
`b11fc85d77172d02aa048d4611a4dbae7c577fbf61fb24dd9806c11d5122a34a`.
Its complete archive/root comparison also passes; originals remain retained.
The qualification
directory preserves both unchanged strict refusals, the complete nonqualifying
observation, all changed rows, physical churn results and the raw resource
summary. Preparation/runtime input maps, media, exact kernel, sampler sources,
generated C, executables, full serial, resource and process-cleanup evidence
remain available with it.
