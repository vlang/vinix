# Inode protections during overlay copy-up

Generic copy-up previously copied data, ordinary metadata and xattrs while
dropping the lower inode's supported flags. An allowed xattr or metadata update
on an append-only file could therefore create an upper file with flags zero,
allowing a later non-append write, truncation or deletion. Copying an append-only
parent could similarly remove its deletion restriction.

Copy-up now installs the supported immutable/append-only bits after preparing
the upper data, xattrs and ordinary metadata, and before switching the merged
alias to that upper resource. Installing them earlier would refuse the internal
data copy. The existing backend setter persists the bits. Unsupported upper
storage and setter failures use the existing rollback path, preserve errno and
leave the merged alias on the lower. Unflagged lower inodes retain their existing
path. Explicit privileged flag changes still pass the original authorization
checks and may subsequently change or clear the copied upper bits.

The maintained V fixture prepares all lower objects before any merged lookup.
Its worker clears supplementary groups and uses UID/GID 1000. Nine cases run
against each of a tmpfs upper, an ext2 upper and an ext2 upper stacked over
another overlay: set/remove xattr, chmod, unchanged chown, current timestamps,
chmod through a held descriptor, appended data, child creation in an append-only
directory and an unflagged control. Descriptors opened before copy-up must see
the new upper flags. Raw upper and lower flags are checked separately; lower
bytes and xattrs stay unchanged, and stacked operations leave the inner upper
absent. Protected files refuse non-append opens, truncation and unlink; protected
directories refuse removal of both new and lower children. The prior privileged
immutable/append flag-clear and held-alias cases also remain in the matrix.
The stacked lower uses a private subtree prepared before merged lookups. Its
names remain linked throughout these cases; unrelated suites can remove their
own names without an outer cached view retaining them.

Two batches each perform 200 metadata-update cycles across all three backends
inside the existing phases 60/61 memory gate. The parent unmounts the additional
overlays and waits 25 seconds for chained retirement before the volume checks.
Writable and read-only ext2 remounts must retain upper flags and contents.

Qualification artifacts are retained in `build/development17-20261013`:

| State | Result |
| --- | --- |
| `protected4-{arm,x86}-before-c` | Previously qualified kernels fail assertion 695: the first xattr copy-up drops append-only flags to zero. |
| `protected3-{arm,x86}-stacked-before-a` | The protection-only kernels retain file protections but fail assertion 697 because an existing stacked lower child is missing. |
| `protected4-arm-stacked-before-c`, `protected4-x86-stacked-before-d` | The same protection-only kernels fail assertion 696 with `ENOENT` in the scoped lazy directory. |
| `protected4-{arm,x86}-basic-a` | Existing portable socket and pathname-xattr checks pass. |
| `protected4-{arm,x86}-linux-a` | The identical basic probe passes Linux 6.12.51-0-virt. This reference covers the existing portable socket probe. |
| `protected4-arm-after-f`, `protected4-x86-after-g` | Protection, flag-routing, authorization, xattr and persistent socket matrices pass, including read-only remount. |
| `protected4-{arm,x86}-all-b` | Protection and existing replacement, failure, retention, whiteout, opacity and writable-remount matrices pass. |

All 19 ARM and 15 x86 live class/large counts match across phases 70/71, 60/61, 50/51,
40/41 and 30/31 as applicable, with zero writes after free. Four final volumes
pass read-only `e2fsck -f -n`. The global allocation audit has 181 remaining
baseline file/kind failures: the separate [event producer fix](security-events.md)
removes both promotion sites in one row, without allowlist changes.

The isolated `kernel-protected4-{arm,x86}-tree` worktrees add this protection
change, the separate [stacked population correction](stacked-population.md)
and the event fix to the qualified inode-flag kernels. They retain the pinned compiler,
legacy pointer-return normalization, link seed 17 and x86 generated sampler.
`protected4-lifetime-review.md` binds independent source/generated-C review to
the final builds. `protected4-evidence.v` checks source and C hashes, fixture
receipts, negative controls, allocation samples, filesystem checks and basic
probe identity with Linux; its record is `protected4-evidence-final.log`.
Initial `protected-*` controls, portable-probe passes and full-suite failures
at assertion 697 and the unbounded `kernel-protected2-*` builds remain separate
from final qualification. Current protection/depth controls use the same scoped
protection and event fixtures as the final matrix. Earlier portable and event
probes retain their pinned fixture versions; whole-probe identity is required
between each native portable probe and its Linux reference.
The original x86 `stacked-before-c` capture stops at the `FAIL:` prefix. Its
separate `stacked-before-d` controller waits for the complete expected failure
diagnostic with the maintained protection/depth/event fixtures; the preliminary
capture is retained.

The x86 `protected4-after-a` and `after-b` runs passed functional checks but
retained 18 and 4 size-96 objects respectively across the socket-only phases
after 25 seconds. The `after-c` runs passed allocation gates at 40 seconds but
their volumes retained orphaned inodes: the whole-root outer fixture cached
unrelated lower names that other suites removed. Scoping the lower subtree fixes
that test interaction; permanent mount ownership still prevents complete cached
view teardown after unmount. The independent review identifies the affected
overlay ACL sockets under `upper`, rather than direct-root sockets.

The scoped x86 `after-d` and `after-e` runs passed functional/remount checks and
read-only fsck but failed the socket gate. Root-parent allocation traces
`protected4-x86-trace-c` and `trace-d` name the measured new slab96 objects as
ext2 metadata page-cache entries. One and sixteen entries match 4 and 64 KiB
growth in `Cached`; the third/fourth extended batches have identical cache and
all 15 live class/large counts. Final socket runs therefore retain two warmup
samples, then compare two batches using the unchanged strict phases 40/41 gate
and 40-second retirement waits. Earlier untraced growth, including the 100 large
allocations in `after-d`, is not reclassified as cache or accepted as passing.
Parent requeues and maintenance-worker delays can extend retirement; this does
not establish a universal cleanup deadline. Older socket-module versions remain
pinned in the portable/full/disk-control probes, where this socket-only loop is
not invoked.
The first warmed x86 run, `after-f`, has flat allocation samples but reached its
600-second deadline during final teardown before remount. The maintained default
is now 900 seconds; the complete x86 result is retained separately as `after-g`.

The final ARM performance checks are `protected4-desktop-perf-c` (ops) and `-d`
(churn, cache, idle, apps and drag). All 36 cohorts of 200 calls retain zero bytes
per operation. Four programs run 300 times each have no live-object growth;
sleep retains one extra 16 KiB size-48 slab page with zero additional objects.
The cache workload writes 32 MiB and retains 16 MiB of cached data. All desktop
scenarios run for five seconds with expected process counts. Independently
extracted boot kernels match the final ARM kernel; checks are recorded in
`protected4-perf-evidence-final.log`. The initial 2 GiB firmware boot timeout
and the 12 GiB run with an insufficient 900-second deadline remain separate;
the final split runs use 12 GiB and the maintained harness's calculated deadlines.

The real backing name already becomes visible during copy preparation. This
change orders protection installation before merged-alias publication; it does
not make direct raw-upper access atomic. Concurrent lower mutation, concurrent
authorization changes, unsupported-backend/error injection, shared mappings,
power-loss recovery, broader flag/capability/namespace/MAC/securelevel matrices
and OCI/rootless-runtime acceptance remain open. Authorized operations that
later fail can still leave copied parents or upper metadata, as before.
