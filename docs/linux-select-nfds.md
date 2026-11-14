# Native select argument words and empty output

Native pselect6 and x86-64 select now interpret `nfds` as signed 32 bits,
ignoring the upper register word. A raw call with `nfds=0x100000021` therefore
checks 33 descriptors instead of returning `EINVAL`. Lower negative values,
including `INT_MIN`, still return `EINVAL`. Linux declares these arguments as
`int` in [fs/select.c](https://github.com/torvalds/linux/blob/v6.12/fs/select.c).

The comparison probe also exposed missing empty-result output. With `nfds=32`
and only bit 32 set, the descriptor is ignored, but Linux still clears the
copied 64-bit result word. Vinix previously returned success with the bit
unchanged. Successful empty timed waits now publish zero result words, and
read-only result sets return `EFAULT`. Interrupted waits leave result sets
untouched. Copies stop at the imported word count; later words and guards stay
unchanged.

## Qualification

Isolated production kernels were built from
`dedc343845de857fc4c75653f078deb1d27486c1` plus the retained pselect.v patch,
using V 0.5.2 `f9ebca4`, `PROD=true LIMINE_MP=1 ALLOC_TRACK=0` and link seed 42.
The original and fixed source input maps differ only in pselect.v. The auditor
compares complete generated C, limiting differences to the public nfds
decoding and `do_select` output. AArch64 contains one syscall decoder; x86-64
contains both. No heap allocation or wait is added. The new zero bitmap is a
16-word stack array borrowed by synchronous usercopy calls. Independent
lifetime review verifies timer/vector cleanup and mask restoration.

The identical static musl ELF for each architecture runs on its original
kernel, fixed kernel and Linux 6.12.51 reference:

| Architecture | Checks | Original failures | Fixed failures | Linux failures |
| --- | ---: | ---: | ---: | ---: |
| AArch64 | 45,780 | 9,612 | 0 | 0 |
| x86-64 | 91,560 | 19,224 | 0 | 0 |

Each root and UID1000/GID2000 cohort covers raw pselect6, plus raw x86-64
select; upper words `0`, `1`, `0x7fffffff`, `0x80000000`, `0xffffffff`; lower
values 0, 32, 33, 64, 65, 1023, 1024, -1 and `INT_MIN`; descriptors 32, 64 and
1022; empty sets, queued UNIX sockets, closed slots and O_PATH handles; all
seven read/write/exception combinations; and read-only empty-result buffers.
Checks require exact return/errno, all three guarded bitmaps and restored
signal masks. Holding descriptor 1023 open aligns Linux's table capacity with
Vinix. All calls use a valid zero timeout and valid mask arguments.

The baseline fails 50 checks per ordinary-upper-word API/cohort and 1,189 per
nonzero-upper-word API/cohort. Its first ordinary-word failure is the ignored
bit at nfds=32. Original probes without read-only controls and the intermediate
width-only builds remain outside the final bundle in the parent workspace;
they are diagnostics, not substituted passing qualification.

Both native cohorts warm 64 cycles, then measure 200 cycles across all APIs,
upper words, empty/ready/closed/O_PATH paths, negative and zero counts, and
read-only empty-result faults. All live slab classes, including all AArch64
medium classes, large-page counts and allocator taint remain flat. The parser
requires complete class layouts and exactly one row per class/cohort, as well
as every expected semantic record. Its controls reject deleted, duplicated,
altered and overflowing records. Generated-C mutation controls reject unsigned
decoding, missing casts/zeroing, heap allocation, incorrect output pointers
and unrelated changes.

Five registered cases compile and pass on each fixed kernel: selectword,
selectfds, selectbad, selectready and JIT. Fresh selectempty and maskwait
compilation fails because the current generator emits unavailable `memdup`
calls. Their failed attempts remain required evidence; unchanged previously
qualified ELFs are replayed against both fixed kernels, alongside O_PATH poll,
to complete eight functional cases. The audit requires these exact compiler
failures and all three successful replays, binding kernel/ELF/image/source pins
and serial output. Existing strict selectfds, empty-wait and O_PATH poll
parsers remain unchanged. Fresh legacy-fixture compilation remained open at
this checkpoint; it is now resolved by the
[fresh-build qualification](linux-wait-fixture-builds.md). The original bundle
and its checker still require these recorded failures and retained replays.

## Evidence and reproduction

Run the maintained `tests/linux-compat/run.v --cases selectword` with an
architecture, isolated kernel directory and fresh state directory. It freezes
both fixture sources and uses a 300-second default budget. Use
`selectword-reference.v --arch ARCH --kernel LINUX --init PROBE --launcher INIT
--state-dir FRESH` for the same-ELF Linux comparison.

The complete external bundle is `/Users/alex/.cache/vx-sw-1114/bundle`, with
original/fixed kernels, generated C, source archive/snapshots, compiler
commands/status/input/output pins, Linux kernels/initramfs, native images,
firmware, serial output and regression receipts. The 691-file manifest has
SHA-256 `210246220e2ef2edd5670ef9d34e6ed8680918fc6b9edd3244ad28bb9b07789b`.

Build `selectword-evidence.v` without `-prod` (`-cc cc -cflags -O2` preserves
checks and speeds hashing), then run:

```
selectword-evidence self-test
selectword-evidence generated ORIGINAL-blob.c FIXED-blob.c
selectword-evidence /Users/alex/.cache/vx-sw-1114/bundle
```

## Remaining scope

This qualifies native argument width and selected empty-result behavior.
Positive counts above 1024, smaller Linux fd-table capacities, full
argument-error precedence, timed/nonzero-deadline output races, partial copy
faults, timeout writeback, GNU wrappers and translated/32-bit ABIs remain
separate. The broader §15 semantics, application installation/integration and
translated-runtime gates remain open.
