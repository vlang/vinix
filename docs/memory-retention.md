# Repeated-path memory retention

The tracking baseline retained 208 bytes per `mkdir`/`rmdir` cycle on both tmpfs
and EXT2: one 192-byte VFS node and its 16-byte name allocation. Rename retained
one old name per operation. Removed directories previously kept their node
forever, even when nothing could use it again. These allocations are now
retired and reclaimed by the periodic worker.

## Ownership and reclamation

A removed directory keeps its resource and its `.` and `..` entries while an
open description, process cwd/root, private thread filesystem view or unlinked
child still uses it. An orphan pins its old parent before its pathname is
removed. Reclamation proceeds from children to parents, so an unlinked file's
descriptor pathname and a removed subtree's `..` traversal remain valid.
Creation and namespace mutations serialize their lookup, removed-parent check,
backend operation and publication under the VFS lock.

The worker waits five seconds for ordinary lockless readers. It checks open
descriptions and child pins before scanning cwd/root owners under their locks.
A busy owner lock conservatively postpones reclamation. Fork publishes its
inherited filesystem state under the process-table lock; private thread views
publish and detach under the thread-list lock. Dropping a cwd/root records a
monotonic release timestamp before the pointer changes, extending the grace
for readers that began through that last owner.

Rename gives every node its own new name and retires the previous owned string.
Overlay upper nodes and visible proxies own separate copies. Retirement batches
transfer their records with `memcpy`: generated V-to-C inspection and the guest
fixture caught an implicit string clone when a string-bearing array element was
pushed into another array, which otherwise leaked the original allocation.

Namespace resource references for removed non-directories are released after
the reader grace, outside the VFS lock. A final PTY callback can therefore
remove its device pathname without recursively acquiring that lock. Directory
resources remain owned by the node until its final reclamation.

## Measurement

The desktop performance harness warms a full cohort of each syscall workload
and waits 13 seconds on both snapshots. A UNIX socket's namespace release can
start another five-second endpoint grace. Deferred inode release also makes a
burst of EXT2 writes use distinct blocks; warming only 20 operations before a
200-operation measurement would count their newly populated page cache as
retention. Its process-churn scenario also warms the full cohort size to reach
the process quarantine's reusable slab capacity, using one native observer
across warmup, workload and snapshots. The former shell observer launched
fresh diagnostic helpers around the after snapshot, leaving
their process corpses and descriptors in the measured delta. The native
observer warms its diagnostic buffers and collects each memory header after
the diagnostic reads touch any fork/COW pages; otherwise its own first buffer
write adds 64 KiB on AArch64.
It validates every child's exit and reports physical retention, slab
objects/pages and allocation sites without those extra helpers.

The [native regression fixture](../tests/memory-retention/README.md) measures
every slab class across three cohorts after warmup and exercises retained
references beyond the grace period. It includes concurrent filesystem mutation,
private thread views, process inheritance and final device callbacks.

Qualification on 2026-10-10 used isolated tracking kernels on four CPUs:
AArch64 with 16 KiB pages and x86-64 with 4 KiB pages. All three native cohorts
passed without positive growth in any of the 18 AArch64 or 14 x86 slab classes.
Both passed the directory descriptor/cwd/subtree and final PTY callback cases.
The diagnostic interfaces are warmed before collecting the control snapshots;
their first access is part of warmup too.

The kernel sources were reviewed independently before qualification and built
over isolated baseline commit `69412419`, with `ALLOC_TRACK=1`, SMP and the TLB
and large-page self-tests enabled. Generated C on both architectures confirms
that retirement transfers do not clone names and the directory-release hook
does not allocate. The qualification matrix was:

| Check | Architecture | Result |
| --- | --- | --- |
| Production kernel build and generated-C ownership audit | AArch64, x86-64 | Passed |
| Native retained-directory and repeated-path fixture | AArch64, x86-64 | Three cohorts; no positive live-object growth in any slab class |
| Desktop syscall retention | AArch64 | All 36 measurements retained zero bytes per operation |
| Native process churn | AArch64 | Two rounds of four programs, 300 measured launches each; zero physical and slab retention |
| Process/SMP, job control, detached churn, resource groups, paging pressure, kernel resources, scheduler/QoS and sparse-file guests | AArch64, x86-64 | All eight suites passed on each architecture |
| EXT2 sparse persistence | AArch64, x86-64 | Create, shrink and cleanup passed for both 1 KiB and 4 KiB blocks, including disk and `e2fsck` checks after each synchronized power cut |
| Desktop idle, apps and drag | AArch64 | Completed without guest errors |
| Performance controller and report contracts | Host | Passed |

The sparse fixture's escaping diagnostic structs now use explicit stack
storage, and its heap bank covers all ARM slab classes. Its original retention
and runtime bounds remain unchanged. The x86 runner also uses the maintained
boot helper rather than an obsolete entry point. These repairs close the
qualification failures without relaxing those bounds.

## Limits

The grace mechanism assumes an ordinary kernel lookup finishes within five
seconds; it is not an epoch-based reader protocol. Mount-covered nodes, overlay
identities and cgroup controller directory identities retain their existing
charged mount/controller lifetimes. This change does not introduce general
mount teardown or reclaim every possible cached or long-lived object.

An unlinked disk inode retains its namespace reference during the grace period.
Raw EXT2 has no journal or crash-time orphan recovery; a power cut while such
an inode remains retained can require filesystem repair, as with an open
unlinked inode. The sparse-file power-cut fixture drains closed unlinked
references before its final sync and consistency check. Crash-safe orphan
recovery remains part of the filesystem roadmap.

The static allocation allowance file predates the current source and compiler.
Both architectures still report the same 170 inherited excess allocation groups;
the allowance was not expanded to hide them. Generated C and live tracking are
used to audit the new repeated paths and ownership transfers. Passing the
measured workloads establishes their bounded retention, rather than proving
that every possible kernel path is leak-free.
