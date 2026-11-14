# Native select descriptor validation

The native select/pselect6 implementation now rejects selected closed descriptor
slots with `EBADF` before polling or writing result sets. An open `O_PATH` slot
remains valid: the `POLLNVAL` returned by the shared polling implementation sets
every requested select bit. `poll` and `ppoll` retain their existing behavior.
This follows the open-slot preflight and `POLL*_SET` masks in
[Linux v6.12 select.c](https://github.com/torvalds/linux/blob/v6.12/fs/select.c).

The previous implementation ignored `POLLNVAL`, clearing closed and `O_PATH`
bits and sometimes returning readiness from other descriptors instead of
`EBADF`. A preflight under `Process.fds_lock` now checks only slot presence.
It releases the lock before polling; the existing ppoll path retains its own
handle references. The existing deferred cleanup frees both select vectors on
the new error return. No resource pointer escapes the preflight.

## Qualification

Evidence was collected on 2026-11-14 from isolated production kernel worktrees
at source revision `5ee08cdc2e07d1d591996eae6b77067ca9f7c83c` plus the retained
`kernel/file/pselect.v` patch. Both architectures use V 0.5.2 `f9ebca4`,
`PROD=true LIMINE_MP=1 ALLOC_TRACK=0` and link seed 42. The complete source
input maps differ only at pselect.v; the auditor compares the entire generated
C and permits changes only to `do_select` and the new helper/declaration.

The same static musl probe ELF runs on each architecture's original kernel,
fixed kernel and Linux 6.12.51 reference:

| Architecture | Checks per execution | Original failures | Fixed failures | Linux failures |
| --- | ---: | ---: | ---: | ---: |
| AArch64 | 54,252 | 19,440 | 0 | 0 |
| x86-64 | 72,336 | 25,920 | 0 | 0 |

The probe covers raw pselect6, musl pselect/select and raw x86-64 select as root
and UID1000/GID2000. It tests closed slots at 63, 64, 95 and 1022, alone and
mixed with ready UNIX socket aliases at 32 or 1000; all seven combinations of
read/write/exception sets; zero, finite and absent timeouts; writable and
read-only result buffers on errors; and exact return values, errno, full
guarded bitmaps and restored signal masks. Ordinary regular files and a closed
bit outside nfds are controls. Open `O_PATH` regular-file, directory and
nofollow symlink handles qualify all requested result bits and their count.
An untimed exception-only ordinary-file wait is excluded to avoid indefinite
sleep.

Both systems hold descriptor 1023 open so Linux and Vinix have matching table
capacity. Vinix starts with 1024 slots, its supported select ceiling, and only
grows the table while a process is live. Linux's initially smaller descriptor
tables are a separate profile; the probe does not claim qualification there.

Each native credential cohort warms 64 cycles, then measures 200 cycles of
closed writable/read-only and open O_PATH calls across every supported API.
All slab live-object classes stay flat, including all AArch64 medium classes.
Large-page counts and allocator taint remain flat:

| Kernel / architecture | Root big pages | UID1000 big pages | Taint |
| --- | --- | --- | --- |
| Original AArch64 | 83/83 | 83/83 | 0/0 |
| Fixed AArch64 | 83/83 | 85/85 | 0/0 |
| Original x86-64 | 222/222 | 222/222 | 0/0 |
| Fixed x86-64 | 222/222 | 222/222 | 0/0 |

The baseline storage checks measure retention despite its expected semantic
failures. The parser requires the exact baseline failures, every semantic row,
both storage cohorts and complete class layouts. Its self-test passes six
positive and 1080 negative controls. Generated-C mutation controls reject
unrelated changes, missing unlock/cleanup, introduced allocation and altered
error/readiness behavior. Independent lock/lifetime review passed. Generated
C contains no allocation, boxing or refcount changes in the helper; select's
allocation/poll counts are unchanged and its new error path releases both
existing vectors.

The registered runner compiles and passes `selectfds` and the unchanged
`selectbad` fixture (2,520 AArch64 / 3,360 x86-64 checks). Seven retained probe
ELFs also pass per architecture: selectready, opathpoll, selectempty, maskwait,
runtime, JIT and execown. These include full regular-file select readiness,
poll's O_PATH behavior, empty interrupted waits and the formerly failing JIT
exec path.

## Reproduction and evidence

Run `tests/linux-compat/run.v --cases selectfds,selectbad` with the documented
architecture, isolated kernel and fresh state directory arguments. Both cases
have a 300-second default budget. `selectfds-reference.v` accepts `--arch`,
`--kernel`, `--init`, `--launcher` and `--state-dir` to boot the identical probe
against Linux. Build host tools without `-prod`; `-cc cc -cflags -O2` keeps
auditor checks enabled and speeds artifact hashing.

The complete bundle is external at
`/Users/alex/.cache/vx-sb-1114/bundle`. It retains original/fixed kernels and
generated C, compiler commands/status/input/output pins, source snapshots,
Linux kernels/initramfs, native images/firmware, serial logs and all regression
receipts. Failed exploratory compile attempts remain in the parent workspace.
The 578-file bundle manifest has SHA-256
`020cc76838f5e0b5d9583c6895f27bf23c6ae2ac447528a4467b8228af1ad302`.

```
selectfds-evidence self-test
selectfds-evidence generated ORIGINAL-blob.c FIXED-blob.c
selectfds-evidence /Users/alex/.cache/vx-sb-1114/bundle
```

## Remaining scope

This closes one native descriptor/error/readiness subset. Concurrent close or
replacement, initially smaller Linux tables, nfds above 1024, complete
argument-error precedence, partial copy faults, timeout writeback, GNU wrapper
behavior and foreign/32-bit ABIs remain separate. The broader roadmap gates
for missing Linux semantics, ordinary application installation/integration and
translated runtime qualification remain open. This patch adds no allocation
sites and makes no claim to resolve the existing global allocation-policy
allowance failures recorded in the exec ownership report.
