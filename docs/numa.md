# NUMA and multi-socket support

A board with more than one memory controller answers a load from another
socket's RAM more slowly than one from its own, so *where* a page comes from
matters as much as how many pages are free. Vinix reads the machine's layout
from firmware and acts on it in the physical allocator, in the scheduler's
thread placement, and through the Linux memory-policy syscalls.

A machine that declares no layout — every uniprocessor and every single-socket
desktop — is one node holding every CPU and all of RAM. Everything below then
turns back into the single-pool, single-queue code it grew out of: the flag
`numa_multinode` stays false and no allocation or scheduling decision changes.

## Discovery

`numa.initialise()` runs after the PMM is up and the higher half is mapped, and
before `smp` hands out logical CPU numbers. It tries two sources:

- **A device tree**, through the `numa-node-id` properties on `/cpus/cpu@N` and
  on each `memory@...` node, plus a `/distance-map` of
  `compatible = "numa-distance-map-v1"`. This is the binding Linux documents in
  `Documentation/devicetree/bindings/numa.txt`.
- **ACPI**, through SRAT for the placement of CPUs and memory and SLIT for the
  distances between nodes. `kernel/modules/numa/numa_acpi.v` walks the R/XSDT
  itself rather than going through the `acpi` module, because that module is
  built around the local APIC and the aarch64 kernel does not compile it — and
  aarch64 under UEFI is exactly where this path matters, since QEMU's virt
  machine hands its guest ACPI tables and no device tree.

On ARM, SRAT names a CPU by its ACPI processor UID while `smp` knows it by its
MPIDR; the MADT's GIC CPU Interface structures carry both, and are read to join
the two.

Firmware's own node numbers (ACPI proximity domains, device tree
`numa-node-id`s) are interned into dense ids counted from zero, which is the
numbering userspace reads back out of `/sys`.

The boot log says what was found:

```
numa: 2 memory nodes from acpi
numa:   node 0 memory 0x40000000-0x80000000
numa:   node 1 memory 0x80000000-0xc0000000
numa:   node 0 distances 10 20
numa:   node 1 distances 20 10
numa: node 0 holds cpus 0x3 and 983 MiB
numa: node 1 holds cpus 0xc and 988 MiB
```

## Allocation

The PMM keeps its single bitmap and its single lock. What NUMA adds is a
classification of that bitmap: each node declares the physical page ranges it
owns, and an allocation for a node scans only those
(`kernel/modules/memory/physical_numa.v`). A node that has run out falls back
to the other nodes in increasing distance, so pressure on one node reaches for
the nearest memory rather than for whatever the global scan walks into.

Per-node free and total page counts are exact: registering a range counts the
pages already handed out inside it, and every allocation and free from then on
is charged to the node that owns the page.

Anonymous memory follows Linux's first-touch rule. The page comes from the node
running the thread that faulted, which is also where a private copy made by a
copy-on-write fault goes.

## Memory policy

`set_mempolicy(2)`, `get_mempolicy(2)` and `mbind(2)` are implemented, with
`MPOL_DEFAULT`, `MPOL_LOCAL`, `MPOL_PREFERRED`, `MPOL_BIND` and
`MPOL_INTERLEAVE`. The policy is process-wide and is inherited across a fork.

`MPOL_BIND` is strict: a fault that cannot be served from the bound nodes
reports ENOMEM rather than quietly allocating somewhere else. `MPOL_PREFERRED`
is a preference and does fall back.

`mbind(2)` has no per-range policy store behind it, so a binding applies to the
process the way `set_mempolicy(2)` does. That is weaker than Linux and
deliberately so: a caller that binds an arena and then faults it in gets its
pages from the nodes it asked for, which is the effect programs use `mbind` for.
Pages already faulted in are not moved, exactly as on Linux without
`MPOL_MF_MOVE`.

`getcpu(2)` reports the node of the CPU the caller is on.

## What userspace sees

`/sys` is mounted with a small sysfs (`kernel/modules/fs/sysfs.v`) carrying the
part of the tree that describes CPUs and memory nodes, because Linux publishes a
NUMA topology nowhere else — libnuma, hwloc, numactl and glibc's
`sysconf(_SC_NPROCESSORS_ONLN)` all read it from there:

```
/sys/devices/system/cpu/{possible,present,online,offline,kernel_max}
/sys/devices/system/cpu/cpuN/topology/{core_id,physical_package_id,...}
/sys/devices/system/node/{possible,online,has_cpu,has_memory,has_normal_memory}
/sys/devices/system/node/nodeN/{cpumap,cpulist,distance,meminfo,numastat}
```

Same file names, same formats. `numastat` reports zeroes: Vinix does not count
the faults that missed their preferred node, and a kernel which never migrates
a page after the fact has nothing else to say there.

## Scheduling

A thread's home node is claimed by the first CPU to run it, and
`get_next_thread()` then runs twice on a multi-node machine: once accepting only
threads at home on this CPU's node, and then accepting anything. A thread
therefore tends to keep running next to the memory it faulted in, while a node
with nothing to do still takes work from a busy one rather than idling.

**On aarch64 this is not yet exercised.** The secondary CPUs are brought all the
way up — per-CPU VBAR, SP_EL1, MAIR, TTBR1, TCR and FP state are all installed —
and then parked without entering the scheduler, so only the boot CPU runs
threads. Releasing them brings up four-way scheduling and userspace then faults:
a thread migrated between CPUs either wedges or takes a null dereference in the
kernel. See the comment in
`kernel/modules/aarch64/cpu/initialisation/initialisation.v`. Until that is
finished, a thread's pages come from the node of the boot CPU, and every other
node is reached explicitly through `mbind(2)` and `set_mempolicy(2)`.

## Tests

`tests/numa/` boots a QEMU machine built with two one-gigabyte nodes of two
vCPUs each, twenty apart, and checks the kernel's own account of it against the
command line that produced it, then checks the topology, `getcpu(2)`, the
memory-policy syscalls and the actual placement of pages from inside the guest.
`tests/qemu-core/` covers the single-node fallback: it boots with no `-numa`
flags at all.
