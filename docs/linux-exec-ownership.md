# Native exec ownership and JIT regression recovery

The JIT slab double-free recorded by the empty-select qualification is resolved
by `49cc3f2cd`: imported arguments and constructed interpreter/translator vectors
own their strings. The identical previously failing JIT ELFs pass on both native
architectures, including ordinary-user approval, read-only runtime mounts,
default W^X enforcement and administrator revocation.

Follow-up measurement exposed a separate leak in that commit's error cleanup.
Every rejected short ELF retained two size-16 objects. Casting stack storage
directly to `&IError` made V allocate a boxed pointer and an interface header;
assigning the real error over that header lost both allocations. The corrected
consumer casts to a concrete `ExecErrorScratch` containing the interface, then
frees the original error object through its stack-resident field.

Allocation tracking reports two groups of 200 live size-16 objects after 200
cycles. Both call chains resolve to `userland__exec_format_error`. The complete
generated-C comparison permits only that function, the concrete wrapper
definition and its two forward declarations to change. The replacement has
no heap allocation and preserves one release of the original error object.
Independent lifetime review found no escaping stack reference, premature release
or double free; error messages remain borrowed literals.

The maintained exec probe checks native ELF execution, interpreter options,
nested scripts, empty argv, long arguments/environment entries, preserved caller
buffers, missing programs/interpreters and short invalid ELF files. Each root
and UID1000/GID1000 cohort warms 64 cycles, then repeats 200 cycles containing
three exec refusals and a successful script exec/fork/reap. All slab classes,
large heap pages and write-after-free counters are measured on both sides.

| Execution | AArch64 checks / failures | x86-64 checks / failures |
| --- | --- | --- |
| Linux 6.12.51, identical probe ELF | 12 / 0 | 12 / 0 |
| Original `49cc3f2cd` production kernel | 14 / 4 | 14 / 4 |
| Corrected production kernel | 14 / 0 | 14 / 0 |

Linux explicitly skips Vinix's two storage checks. Original kernels retain
400 size-16 objects in each 200-cycle cohort; the four reported failures include
each failed cohort's exit status. Corrected kernels keep every slab class flat,
with 69 AArch64 and 160 x86-64 large pages unchanged and zero write-after-free
counts. The ordinary original and corrected comparisons use identical probe
ELFs; allocation tracking is a separate diagnostic boot.

Nine maintained suites pass on each corrected architecture: selectempty,
maskwait, resethand, sigmaskcopy, altstackrestore, sigwaitorder, seccomp, runtime
and jit. JIT identities are pinned to the original failing ELFs, rather than
recompiled replacements. The exec Linux reference controller now waits for its
actual `LINUX EXECOWN REFERENCE: PASS` marker and produces a successful receipt.
The original incomplete reference attempts remain in the earlier workspace.
The first maintained altstackrestore launches exceeded macOS's QMP socket-path
limit and never booted. Their failed receipts/logs remain in the bundle beside
the successful identical-ELF retries from shorter paths. The registered
`run.v --cases execown` path also passes on both architectures and the auditor
requires both frozen fixture sources.

Both isolated builds use base revision
`49cc3f2cddedf6a04efebac73b940e91111646f4`, the retained candidate patch,
V `f9ebca4`, `PROD=true`, `LIMINE_MP=1`, `ALLOC_TRACK=0` and link seed 42.
AArch64 uses four virtual CPUs and 16 KiB pages; native x86-64 uses two virtual
CPUs and 4 KiB pages. The separate tracking build enables `ALLOC_TRACK=1`.

The allocation-source scanner completes on both architectures: 716 files / 379
sites on AArch64 and 715 files / 279 sites on x86-64. Baseline and candidate have
identical counts in all 209 file/kind groups, with no new sites. The repository
allowlist check still fails on both with the same 177 excess groups. That
pre-existing policy failure is retained; this report does not claim the global
allocation gate passes or change its allowlist.

Broader guards use these same corrected kernels. All 36 common-operation
cohorts per architecture repeat 200 calls with zero retained bytes and no
changed slab classes or large-page counts. All four short-program churn cohorts
repeat 300 executions on each architecture with zero retained memory and no
slab changes. Idle, application startup and drag boots complete; full screenshots
show actual window movement on both architectures. The final ARM startup boot
also verifies live Files, Terminal, Clock, Calculator and Activity Monitor clients
and shows their five windows. Performance boots use 4 GiB and four virtual CPUs;
these are bounded kernel/desktop smoke checks, not application lifecycle tests.

Preparation failures remain visible. The first ARM combined run completed all
36 operation rows, then failed curl churn because the local wrapper had applied
an x86-only overlay. Its early churn also recorded three decreasing slab classes;
that composite run remains failed. Correct ARM-native churn/cache and desktop
boots run separately. Initial ARM desktop snapshots opened fewer requested
clients; a newer existing desktop and matching native aliases qualify the final
five-client boot. An initial 1024x768 drag run moved icons rather than its System
window despite controller status zero; only the later 2048x1536 screenshots
qualify window dragging. The standard host launcher also hit existing C.poll
declaration conflicts, so the retained native VM launcher supplies these boots.

The execution workspace is
`/Users/alex/.cache/vinix-linux-compat/execown-final-20261114`.
Its `bundle` directory retains original/corrected kernels, generated C,
source archive/patch/snapshots, build and compile receipts, Linux and native boot
images/logs, original failing results, maintained ELFs, allocation diagnostics
and the lifetime review. Its 697-file manifest SHA-256 is
`15341d227aecbd3de94e29feab1dd29ea11949cac6426184aa51fbb210bb5dc4`.
The complete evidence audit passes. Source-policy and broader desktop/retention
receipts are retained alongside this focused bundle in the workspace.
The separate typed performance inventory covers successful and failed run
directories, every payload's bytes/mode, directories and link targets. Its SHA-256
is `52229166d04a65cd42abfc45fb7fe3262d3d10ba144ef3c515e909cfd573a0de`.
`execown-perf-evidence.v` binds that inventory to the focused kernel manifest,
checks all 36 operation identities, complete maintained performance transcripts,
zero churn retention, absence of growing slabs and the final five live ARM
client names. Its record mode refuses to overwrite receipts; check mode reads
the retained receipts without changing them. Compile this macOS controller with
`-cc cc -cflags '-O2 -include stdlib.h' -path 'tests/desktop-perf|@vlib'`.

The strict V evidence checker verifies the complete inventory, original
retention, unchanged comparison ELFs, successful Linux/native receipts, exact
cleanup classes, generated-C scope and all nine maintained cases. Its controls
include seven valid and 218 rejected serial cases, two valid and 34 rejected
ownership cases, and one valid and five rejected generated-C scope cases.
Both complete AArch64 allocator layouts from the retained V builds are accepted;
mixed, missing, repeated or growing candidate classes fail, as do differing
allocator layouts between a kernel's two privilege cohorts.

```sh
v -cc cc -cflags -O2 -path 'tests/linux-compat|@vlib' \
  -o /external/execown-evidence tests/linux-compat/execown-evidence.v
/external/execown-evidence self-test
/external/execown-evidence check /external/restored-bundle
```

This qualifies selected native musl exec behavior and cleanup. GNU libc,
translated x86-64/i386 execution, concurrent input mutation, allocation pressure,
full execveat/descriptor policy and application install/update/save integration
remain separate. The roadmap's broad libc, application lifecycle/sandbox and
AArch64 translation gates remain open.
