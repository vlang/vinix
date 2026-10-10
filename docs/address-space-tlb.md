# Address-space tags and kernel large pages

X86 address spaces own globally exclusive PCIDs 1–4095. Zero remains the
kernel context and the fallback when the pool is exhausted. Every CPU checks
PCID and INVPCID before going online; any unsupported CPU vetoes tagged user
contexts before their creation. `-d no_pcid` also disables retention. Physical
root pointers stay untagged; saved scheduler CR3 values include the PCID, and
switches between tagged roots set the hardware no-flush bit.

A tagged map may remain cached on a CPU after that CPU switches away. Every
mutation therefore targets all online CPUs, including inactive contexts.
INVPCID type 1 removes the map's translations and paging-structure caches.
Shared kernel changes use type 2 on every CPU. Untagged maps retain the existing
active-map recording/fencing and INVLPG path. The synchronous IPI protocol also
services requests from interrupt-disabled lock spins, avoiding a shootdown
waiting behind the lock held by its caller. See the
[Intel SDM INVPCID reference](https://cdrdv2-public.intel.com/868140/253666-089-sdm-vol-2a.pdf).

Teardown drains map owners and inspection references, invalidates the owned
context before removing ranges/tables, and invalidates it again before freeing
the tag. The bitmap bit stays set through every remote acknowledgment. Only
then can another map acquire that PCID. Pool exhaustion uses zero, without
stealing another live owner's tag. Pool, locks and descriptors use bounded
static or stack storage; switching and tag management allocate nothing.

Thread-list removal and scheduler handoff also have to retire the hardware
root before another CPU can free it. Exit switches to the kernel map before
removing itself from the process. X86 saves the outgoing CR3, then switches
hardware to the kernel root while the thread lock and on-CPU marker still
protect it. A Process pin survives detached-thread cleanup, tid release and
final CPU accounting; the Thread changes its process pointer to the kernel
process before releasing the pin. This closes the freed-root triple fault
found by the 600-worker scheduler regression and prevents a delayed exiting
thread from referring to a Process already reaped by its parent.

ARM retains its existing 255 exclusive eight-bit ASIDs, non-global user leaves,
broadcast break-before-make and invalidation before tag reuse. ASID zero remains
the full-flush fallback. The shared tests now explicitly cover inactive remote
CLONE_VM processes as well as active threads, fork/COW and exec replacement.
The same-CPU switching test also covers ARM's idle-stack handoff: a speculative
run-queue selection returns its candidate to the queue head before releasing
the candidate's lock. The second scan then reaches the waiting process before
the process that just yielded, without retaining a thread pointer across the
stack change.

X86's direct map uses 2 MiB supervisor, writable, non-executable leaves where
a complete aligned interval lies within one usable-RAM firmware entry and has
a verified uniform write-back MTRR type. A bounded boot snapshot checks every
enabled variable MTRR. A partial intersection or any matching non-WB range
rejects the candidate; an unmatched candidate requires a WB default. Fixed
MTRRs below 1 MiB, reserved/MMIO/firmware regions, memory-map boundaries, unknown
features and malformed masks retain 4 KiB leaves. Firmware MTRRs are assumed
consistent across CPUs and are not reprogrammed by this implementation. The
[Intel SDM large-page memory-type rules](https://cdrdv2-public.intel.com/868137/325462-089-sdm-vol-1-2abcd-3abcd-4.pdf)
require uniformity; the guard deliberately rejects uncertain spans.

Each large direct-map leaf avoids one 4 KiB last-level table and replaces 512
base-leaf entries. It introduces no contiguous-allocation requirement for user
pages. Queries return the existing base-page physical-address contract,
including a subpage inside a large leaf. Walkers never descend through a large
leaf as though it were a table.

Changing, protecting or removing one child first reserves and allocates a
4 KiB table. It initializes all 512 equivalent children, including PAT conversion
and conservative accessed/dirty bits, then publishes one table descriptor.
The kernel shootdown completes before the caller changes that child. Allocation
failure rolls back the reservation and leaves the old large descriptor intact.
Existing empty-table retirement invalidates before returning pages to the PMM.
Kernel text/rodata aliases still become read-only, and guarded VMAP stacks keep
base pages. Existing small tables are never re-promoted or freed during setup.

This completes the bounded CPU tag scheme and a concrete kernel large-page use
case. Explicit userspace huge-page mappings (VM6), automatic promotion,
16-bit ARM ASIDs/generation rollover, ARM kernel block demotion and GPU address
space tags remain separate work. User COW/shared mappings, anonymous pageout,
file writeback, quotas and residency accounting retain their base-page contracts.
These correctness tests do not establish a physical-hardware speedup or power
saving. QEMU system TCG lacks PCID/INVPCID, so native x86 tests exercise the
conservative switch path and real large-page transitions. Host tests cover
PCID policy; enabled-PCID physical-hardware/KVM qualification remains. See
[qualification](../tests/tlb/README.md) for coverage and limits.
