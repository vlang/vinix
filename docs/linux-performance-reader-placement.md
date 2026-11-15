# Native slab-reader placement

A standalone reader can increase an ARM slab class's backing pages without
retaining objects or running an application workload. In the first two-CPU
capture, the cold cross-CPU reader pair changes class 512 from 15 to 16 pages,
with objects unchanged at 423. A second fresh ARM capture repeats that change
and also changes class 1536 from two to three pages with objects unchanged at
12. The first x86 capture is flat; its repeat changes classes 512 (72/73 pages,
497/497 objects) and 1536 (8/9 pages, 13/13 objects) in the cold pair. All 12
warmed pairs across these four captures are flat. This supports observer
placement as a source of page changes; it does not establish the cause of every
delta in the preceding fixed workload.

`heap-placement/main.v` uses the existing strict `perfheap` reader and selected
schema. It saves the native affinity mask, requires exactly CPUs 0 and 1,
selects a CPU and verifies `sched_getcpu()` before accepting each snapshot.
Both snapshot buffers, their delta and affinity masks use stack storage in the
retained generated C. The initial buffer touches run on CPU 0. Each of four
cases has 64 reader warmups per selected warm CPU, a 13-second grace wait, the
before snapshot, 200 reads, another 13-second wait and the after snapshot:

| Case | Reader warmup | Before CPU | After CPU |
| --- | --- | ---: | ---: |
| 0 | CPU 0 | 0 | 1 |
| 1 | CPUs 0 and 1 | 0 | 1 |
| 2 | CPUs 0 and 1 | 1 | 0 |
| 3 | CPUs 0 and 1 | 0 | 0 |

The diagnostic emits every ordered object/page pair, large pages and both
written-after-free counters after each pair. It restores and rereads the
original mask before its completion marker. Native placement, complete schemas
and zero corruption counters are required; changed object, backing-page or
large-page counters remain visible. Every capture and checker result explicitly
sets `qualification=false`. No kernel allocation or lifetime code changes, and
no workload, sampler warmup or strict flatness policy changes.

The host launcher runs an initramfs-only guest with two CPUs, 1024 MiB RAM, no
network and a 300-second deadline. It pins the ELF, copied initializer, kernel,
ISO, initramfs, emulator, read-only firmware and launch inputs before/after the
capture. PID1 pauses after completion; the maintained session owner retires the
emulator process group. `forced_cleanup=true` records this deliberate stop and
does not claim a natural guest exit. ARM uses HVF; x86 uses TCG.

The checker requires exact cases, order, schema, class coverage, canonical u64
counters, corruption counters and affinity restoration through complete EOF
rows. It accepts only the selected console's terminal CR sequences. Public
host tests run its 187 ARM-profile and 156 x86-profile controls in normal and
production modes, alongside the unchanged reader and full-workload controls.
Changed-storage controls must report changes without qualifying them.

The selected kernels are the production, `ALLOC_TRACK=1`, `LIMINE_MP=1`, seed-42
builds from the preceding supervised run: isolated source
`cab44e91988c37aae1bab7af0fe7183dcd5ddd8a` plus the qualified procfs builder fix.
The test sources are retained from checkout `7e47cc23d` plus this change. The
host frontend is frozen `cbfc1be` with its complete tracked tree at
`7a51d7a21849d86d09280dbc168f8fffe7c1dbca`. Both payloads use the verified
compiler `53debcfe66952ba952d64b2b94dbb2408bed6992453d1ac6bad5889e4bd1ec7e`,
isolated from the host compiler's standard library. Static musl links keep
`-Werror=format` and `-Werror=incompatible-pointer-types`; the x86 link also
needs `-D_GNU_SOURCE` for the native affinity declarations. Initial rejected
pointer/feature-macro attempts remain in external logs. Installed SDK and
emulator dependencies are not claimed hermetic.

The slab implementation keeps an empty spare page per class and CPU shard.
`heap_classes()` samples shards under individual locks rather than one global
lock. The procfs reader allocates its text and class array, so reader allocations
can affect the observed classes. The cold-reader captures demonstrate an effect
in classes 512 and 1536 on both architectures; they do not prove that every
original class 256/512/1536 change is a reader spare. The diagnostic also has a
smaller boot environment and memory size than the fixed six-scenario run.

The previous strict six-scenario result remains rejected for all four published
backing-page deltas. The inherited allocation-allowance refusal and broader
section 15 application/ABI acceptance gates remain open. See
[the original run](linux-performance-supervised-compilers.md).

Evidence is retained at `/Users/alex/.cache/vx-hp-1115/bundle`, archived as
`/Users/alex/.cache/vx-hp-1115.tar.gz` with SHA-256
`afc4d25116e94daa4e8cdd76eee2a97f8626981ea0e9d2245b59d28a996963f8`.
The unchanged archive checker passes its complete logical root comparison,
including file bytes, modes, directories and literal links. The bundle includes
all four captures, generated C, strict build commands/logs, executed ELFs and
kernels, launch media, before/after pins, checker outputs and public test state.
`observations.json` records 256 class pairs: no object or large-page changes,
five backing-page increases confined to cold pairs, and zero corruption counters.
The final ARM/x86 serial hashes are
`d9efd705109c0f4a7802cc5c2dc043b5a7464c4408f84f6269edd35370b75090` and
`1a82092c35ef9902dfca914b9b9cee4a7aa02fd5c463861e28189574f12d7798`.

`dependencies.json` pins the preceding complete compiler/preparation and
instrumented-kernel source bundles described in
[the supervised run](linux-performance-supervised-compilers.md); both archive
checksums are verified again. Original captures and source/compiler dependencies
remain retained; no evidence is retired.
