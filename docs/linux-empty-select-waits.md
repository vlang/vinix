# Native empty select waits

An empty descriptor set and NULL timeout now sleep until a handled signal
interrupts select or pselect6. The shared select implementation calls the
existing synchronous ppoll sleep instead of returning EINVAL. A pselect mask
remains active during the wait and handler; sigreturn restores the original
mask. An ignored signal leaves the wait sleeping, and SA_RESTART does not
restart this family of waits after a handler.

The static musl probe for each architecture runs unchanged on Linux 6.12.51,
the original Vinix kernel and the corrected kernel. It covers:

- Raw pselect6 and musl pselect/select on both architectures, plus raw select
  on x86-64.
- nfds 0, 1, 65 and 1024, NULL or guarded empty read/write/exception sets,
  root or UID1000/GID2000, and SA_RESTART off/on.
- Signals queued before a masked wait and signals sent after a sibling
  observes the caller sleeping through its task stat record. The sibling
  sends ignored SIGWINCH, observes sleep again, then sends handled SIGUSR1.
- Exact EINTR, handler masks, restored masks, untouched bitmap guards,
  zero-timeout returns and real finite timeout expiration.

| Execution | AArch64 checks / failures | x86-64 checks / failures |
| --- | --- | --- |
| Linux reference | 2,176 / 0 | 2,752 / 0 |
| Original production kernel | 2,176 / 576 | 2,752 / 704 |
| Corrected production kernel | 2,176 / 0 | 2,752 / 0 |

Each Vinix boot also warms 64 calls, then measures 200 repeated empty pselect6
waits in separate root and UID1000 cohorts. Every live slab class, the large
heap page count and the write-after-free counter stay flat. Corrected cohorts
complete 200 EINTR deliveries each; original cohorts explicitly consume the
200 signals left queued by their EINVAL refusals. AArch64 retains 69 large
pages and x86-64 160. The reference boot explicitly skips this Vinix heap
inspection; it still performs all semantic cases.

Eight of nine selected maintained suites pass on each architecture: selectempty,
maskwait, resethand, sigmaskcopy, altstackrestore, sigwaitorder, seccomp and
runtime. The JIT policy fixture panics with `Slab: double free`. Its identical
ELF reproduces that panic on both original kernels as well as the corrected
kernels; all four controls and the original failed suite results are retained.
That baseline failure remains unresolved. Vinix AArch64 uses four virtual CPUs and 16 KiB pages;
Vinix x86-64 and both Linux references use two virtual CPUs and 4 KiB pages.

The isolated build base is `94f80b38ef5487959e9a1124d85cf8ecae602a15`.
Both original and corrected architectures build with V `b25b2d9`, PROD=true,
LIMINE_MP=1, ALLOC_TRACK=0 and link seed 42. The base source archive and
candidate diff are retained. Full generated-C comparisons find only do_select
changed. Allocation/release operation counts are unchanged; the new call uses
ppoll's existing stack event and synchronous listener cleanup.

The execution bundle is
`/Users/alex/.cache/vinix-linux-compat/selectempty-evidence-20261104`.
It retains source snapshots, the source archive/diff, compiler/build receipts,
original/corrected kernels, generated C, probe and reference launcher ELFs,
boot images, raw logs and failed attempts. Its SHA-256 inventory checksum is
`18fce85a3c78cbccb15315b3e9ca8e0c46a4141fe0ac85c02cc0a18d73da640b`.

The V checker verifies the full file inventory, every semantic case and
original mismatch stage, exact probe/kernel identities, all heap classes,
generated-C scope and the nine maintained receipts, including the failed JIT
case and mandatory identical-ELF before/after panic controls. Its parser passes four
positive and 6,072 negative controls. Compile it without -prod:

```sh
v -path 'tests/linux-compat|@vlib' -nocache -cflags -O2 \
  -o /external/selectempty-evidence tests/linux-compat/selectempty-evidence.v
/external/selectempty-evidence self-test
/external/selectempty-evidence check /external/restored-bundle
```

The maintained runner accepts `--cases selectempty`. The shared host
controller accepts `VINIX_COMPAT_CASE=selectempty` for probe compilation and
standalone Vinix boots; its default remains maskwait. Retain the documented
native guest support tree and musl SDK to reproduce those local controllers.

Failed preparation attempts remain visible. The older V compiler rejects the
checkout's migrated uint types; all final kernel builds use the current
compiler. Early fixture compilation errors are retained. The first AArch64
Linux reference exposed a two-second observer cutoff; the final probe requires
both sleep observations and uses only the child watchdog to bound the wait.
The corrected probe passes both reference boots and both Vinix architectures.

Descriptor-bearing select behavior, cancellation, stop/continue races,
timeout writeback, complete argument/error ordering, GNU libc and foreign or
32-bit execution need separate qualification. Section 15's three broader
libc, installation/integration and AArch64 translation gates remain open.
Linux's reference behavior is implemented in
[fs/select.c](https://github.com/torvalds/linux/blob/v6.12/fs/select.c).
