# Immutable x86 boot-media reuse: host qualification plan

This is a source-only proposal. No new compiler, generator, preparation or VM
has run for this profile. The interrupted R2 bundle remains frozen at complete
literal inventory `c1bb658176983b19d8c2f907f85a426fa9ac91006ed14e5b9f6ca7a63dd4a763`.
The separate implementation cannot recover its missing statuses or qualify its
partial transcript.

The new `prepare-reuse-source.v` generator reads the frozen runtime worktree's
foreground-owner source, checksum
`413a2e8b540169cbcf6a7728105b38044260d5548722cfb40f2d5c4ec523eb1d`,
removes its sole public entry and appends the new fixed reuse entry. Its budget,
sourcecommand ownership, wait/reap, cleanup and final timing functions remain
literal donor code. The old source and qualified executable are untouched.
The separate library constrains the new contract; the existing qualified
owner's `run` entry is intended to supervise the eventual new adapter.

The explicit new preparation contract creates one blank 256 MiB ext2 disk,
copies four small manifests and emits a new Prepared-compatible receipt with
storage `immutable-media-reuse`. It does not claim a new rootfs clone or build.
All original Prepared pins except its single historical writable-disk hash
remain required. The complete frozen R2 inventory independently binds that old
disk's current content too. Five fresh literal inventories (whole R2, base,
staged rootfs, sysroot and GCC) are checked before and after preparation and
runtime. Guest absolute links remain literal. Full fixed QEMU argv reconstruction
allows only the new disk and new socket slots to differ. Results are new; the
old directories and socket are retained.

New host artifacts belong under
`C/perf-runtime-host-20261105-01/reuse-adapter-host-01` (`H`), where
`C=/Users/alex/Library/Caches/vinix-codex/section14`. Every attempt, failed C file,
private cache, source copy, log, control and receipt counts against **32 MiB
cumulative new growth**. No old artifact may be deleted to make a retry fit.

| Cumulative host allowance | MiB |
| --- | ---: |
| Independent source copies, generated source and complete input maps | 5 |
| All generator attempts, C, executables, private caches and scratch | 3.5 |
| Normal C, executable, private caches and scratch | 5.5 |
| Production C, executable, private caches and scratch | 5.5 |
| Both 4 MiB ext2 controls and other retained fixture data | 9 |
| Logs, journals, reports and all failed-attempt output | 1.5 |
| Unspent final reserve | 2 |
| Total | 32 |

This is a forecast, not permission to overwrite a failed attempt or consume the
tail. Admission before each compiler/control must charge actual previous
attempts plus the whole remaining increment and final reserve. If any ceiling
is exceeded or the forecast no longer fits, stop. The donor's retained C was
2,145,005 bytes normal and 2,148,433 bytes production; its production executable
was 617,616 bytes. The new 5.5 MiB per-build allowance includes additional contract
code and cache/scratch, and must be checked against actual generated output.

Select the existing complete pinned V installation
`/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain` and its `v` executable
SHA256 `ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`.
Use explicit clang23
`/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23`
(`4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8`)
and MacOSX26.5 SDK. Clear inherited tool overrides; keep coherent V/VEXE markers
and private HOME, TMPDIR, VMODULES and compiler caches inside H. No global cache,
kernel toolchain or SDK mutation is allowed. Compiler/source/include maps and
direct executable pins require complete before/after comparisons. This is not
a hermetic host loader/SDK dependency claim.

First build the source generator with `-backend c -gc none -nocache -keepc`, explicit clang/SDK and
pointer/format errors. Run it once into a fresh H source directory, inspect the
generated donor delta and record its complete source map. Then build that exact
generated main in normal and `-prod` modes with `-backend c -enable-globals -nocache -keepc`,
the same compiler flags, and explicit module paths selecting the new source plus
the frozen runtime worktree's `tools`, `tests/desktop-perf`,
`tests/hardware-platform` and `tests/linuxkpi`. Retain all actual argv/environment,
C, binaries, logs and statuses. No generator or build has yet been admitted.

Each binary must pass `selfcheck-reuse` in its own fresh state. Controls must
exercise contract mutations (content, missing/added entries, mode and link
changes, original pin/command/workload changes, extra mutable exemptions,
aliased/existing destinations and stale sockets), actual zero/nonzero/deadline/
output/interruption/held-pipe ownership paths for both the outer preparation
owner and each fixed helper, and one real 4 MiB ext2 fixture
using the production mkfs flags. The small ext2 fixture must be refused as a
production 256 MiB disk. Neither control mode executes QEMU or writes R2.

After host checks, source/compiled-C/ABI review and independent receipts are
required before any preparation. The future output root would be
`C/perf-six-x86-reuse-20261105-01` (R3), a fifth nonoverlapping charged root.
W, S, R1 and frozen R2 all remain charged. The closure endpoint of 3,618,877 KiB
apparent plus 262,144 KiB for the blank disk, the complete 786,432 KiB remaining
reserve, 32,768 KiB for all new host work and 8,192 KiB for preparation maps,
logs and receipts totals 4,708,413 KiB, below the unchanged 4,718,592 KiB ceiling
by 10,179 KiB. Preparation checks that inclusive projection before creating R3
and again before launching its child; after preparation the complete 768 MiB
reserve must remain available. Fresh measured usage may invalidate that
forecast. Existing 2/1 GiB free-space floors, 32 MiB runtime output bound
and 2400/2520 second guest/owner deadlines remain unchanged. No preparation,
runtime profile, disk creation, original-audit consumption or VM is authorized
by this source-only plan.
