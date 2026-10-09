# Kernel resource reservations

User-created kernel metadata and buffers now require reservations before their
allocation on AArch64 and x86_64. Failed admission returns an ordinary syscall
error and leaves close, unmap, IPC removal and exit able to finish. This extends
the existing physical-memory reserve and OOM recovery to resources that can grow
without a large user RSS.

The global reservation limit is one eighth of RAM, clamped to 2–512 MiB. Each
creator account can hold half that limit. Fixed account slots carry generations;
objects retain the account independently of the Process lifetime. A shared map,
queued SCM_RIGHTS description, removed-but-attached shared segment or accepted
socket therefore keeps its creator's identity after that creator exits. Fork
charges the child's private metadata and descriptors; it retains shared backing
without copying its reservation. This is creator accounting, not a cgroup charge
migration policy.

`/proc/kernel-resources` reports the limits, total reservations, live accounts,
admission denials and object/byte totals for files, descriptors, sockets, IPC,
mappings, processes, threads and syscall scratch. These are conservative capacity
reservations, including allocator rounding and replacement-buffer peaks, rather
than measured slab RSS. There are 4096 account slots. Additional global limits
bound live reservation records: 65536 each for file, descriptor and mapping
classes; 4096 for socket, IPC and process classes; 256 for user threads; and 512
for scratch. Existing syscall and RLIMIT limits also apply.

The charged paths cover:

- File descriptions, descriptor tables and copies, created VFS nodes, tmpfs
  resources, sparse page-slot metadata, directory listings and tmpfs attributes.
- UNIX endpoints, accepted connections, receive buffers, backlogs, packet
  records and passed descriptors; native Internet socket pool reservations;
  netlink buffers and reply scratch. UNIX packet metadata and backlogs each
  stop at 4096 entries, including zero-byte packets.
- Pipes/FIFOs, epoll registrations and wait snapshots, inotify instances and
  SysV semaphore sets, shared segments, message queues and queued messages.
  Each SysV registry stops at 4096 entries; tmpfs attributes stop at 256 per file.
- PTY pairs, endpoint boxes and fixed input/output rings. Device aliases retain
  their backing endpoint through unlink and blocking or failed opens.
- Mapping aliases and global shadows, including an account pin for an untouched
  lazy shared map. User page-table roots and intermediate tables are charged
  as allocated, and returned on pruning or address-space disposal.
- Processes, kernel stacks, thread state, command-line snapshots, bounded
  exec-vector copying and temporary file/socket/poll buffers.

Admission never sleeps or invokes reclaim under resource locks. Physical
admission keeps the lower half of the existing critical reserve for kernel
cleanup; small syscall metadata can use its upper half, like user-copy faults.
Physical denial requests the existing OOM recovery after syscall locks unwind;
quota denial returns ENOMEM (or the resource's existing exhaustion error).
OOM victim scoring now includes live creator reservations alongside resident
user memory. A quota denial does not itself kill another process.

Failure paths return unpublished references and reservations. Overlay creation
keeps a replaced whiteout through identity/ACL initialization; failed initialization
restores it without allocating another whiteout. Unlink and rename preallocate
needed whiteouts before changing names. Blocking opens pin both the VFS node and
its origin resource, including a device factory that returns a different resource.

Reservations remain while retired memory remains allocated. Removed nodes and
UNIX endpoints use the existing grace periods. Expired Process quarantine entries
are also reaped by the periodic worker, rather than requiring another exit.
Retirement only queues work; the unlocked worker performs final resource releases.
PTY pathname removal checks endpoint identity under the VFS lock, so a stale
close cannot remove a reused device number. Pair memory waits a fresh grace period
after its last retained backing reference is released.
The scheduler still keeps one most recently dead thread stack per CPU until a
later death there. Removed directories and independently pinned overlay/mount
nodes retain their existing lifetime policy and stay charged while retained.
Boot objects and internal kernel tasks have no creator account; page-cache/data
pages continue to use the existing physical-memory policies. This change does
not implement resource-group ownership or eliminate every historical retention
site; those remain separate roadmap items.

See [acceptance tests](../tests/kernel-resources/README.md).

Validation includes both architecture builds and native exhaustion fixtures,
concurrent host accounting tests, paging and mapped-writeback pressure regressions,
exact retained-object checks for resource opens, and desktop idle/apps/drag boots.
The allocation-warning audit still fails inherited allowance groups; these were
compared with baseline without expanding the allowances. Historical rename-name
and removed-directory retention remains separately tracked by the roadmap.
