// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// NUMA and multi-socket topology.
//
// A board with more than one memory controller answers a load from another
// socket's RAM more slowly than one from its own, so where a page comes from
// matters as much as how many pages are free. This module reads the firmware's
// account of that layout and turns it into three facts the rest of the kernel
// acts on: which node each CPU belongs to, which physical pages each node
// owns, and how far apart two nodes are.
//
// Discovery has two sources. ACPI's SRAT and SLIT describe it on anything that
// boots through UEFI, which on this tree includes the aarch64 QEMU machine as
// well as every amd64 one. A device tree describes it through `numa-node-id`
// properties, which is what a machine booted without ACPI provides.
//
// A machine that declares nothing is one node owning every CPU and all of RAM,
// which is what a uniprocessor and a single-socket desktop are. `numa_multinode`
// stays false there and every addition to the allocator and the scheduler turns
// back into the single-pool, single-queue code it grew out of.
@[has_globals]
module numa

import memory
import proc
import usercopy
import errno

pub const max_nodes = 16

// One range per firmware memory-affinity entry. Two per node is the usual
// shape; eight leaves room for a board that reports its RAM in pieces.
pub const max_node_ranges = 8

// Logical CPU numbers are dense, and the scheduler's affinity masks are 64-bit,
// so a node's CPU set is too. The table is larger because a hardware id table
// is indexed by firmware's ordering, not by ours.
pub const max_cpu_slots = 256

pub const distance_slots = max_nodes * max_nodes

// SLIT values. Ten is "as close as a node gets to itself" and everything else
// is relative to that, so 20 is the conventional "one hop away".
pub const local_distance = u8(10)
pub const default_remote_distance = u8(20)
pub const undeclared_distance = u8(0)

pub const no_node = -1

// MPIDR_EL1 carries more than the affinity fields -- bit 31 is reserved as one,
// and MT/U report topology rather than identity. Only Aff0..Aff3 name the CPU,
// which is what both a device tree's `reg` and an MADT's GICC structure hold.
// Defined here rather than in the aarch64 file because the ACPI walker, which
// is compiled for both architectures, applies it to what the MADT reports.
pub const mpidr_affinity_mask = u64(0xff00ffffff)

// set_mempolicy(2)/mbind(2) modes, from linux/mempolicy.h.
pub const mpol_default = 0
pub const mpol_preferred = 1
pub const mpol_bind = 2
pub const mpol_interleave = 3
pub const mpol_local = 4
pub const mpol_max = 5

// get_mempolicy(2) flags.
pub const mpol_f_node = 1
pub const mpol_f_addr = 2
pub const mpol_f_mems_allowed = 4

pub struct Node {
pub mut:
	present bool
	// Firmware's own name for the node: an ACPI proximity domain or a device
	// tree numa-node-id. Kept so a log line can be checked against the host
	// configuration that produced it.
	domain      u32
	cpu_mask    u64
	range_count int
	range_base  [max_node_ranges]u64
	range_size  [max_node_ranges]u64
}

__global (
	numa_nodes [max_nodes]Node
	// Nodes are numbered densely from zero in the order firmware declared them,
	// which is the numbering userspace reads back out of /sys.
	numa_node_count = int(0)
	// True once more than one node was found. The PMM and the scheduler test
	// this before doing anything differently, so a single-node machine pays for
	// none of it.
	numa_multinode = false
	// Row-major, [a * max_nodes + b]. Zero means firmware did not say.
	numa_distances [distance_slots]u8
	// Logical CPU number -> node, valid once attach_cpus() has run.
	numa_cpu_nodes [max_cpu_slots]int
	// Hardware CPU id -> node, exactly as firmware declared it. The topology is
	// read before smp runs, so logical numbering does not exist yet and the
	// hardware identifier is the only name a CPU has.
	numa_hw_count = int(0)
	numa_hw_ids   [max_cpu_slots]u64
	numa_hw_nodes [max_cpu_slots]int
	// Where the topology came from, for the boot log and for /sys readers who
	// want to know whether anything was actually discovered. A code rather than
	// a string: this is written before the V runtime has a heap to put one on.
	numa_source = int(source_none)
)

pub const source_none = 0
pub const source_devicetree = 1
pub const source_acpi = 2

// ── Discovery ────────────────────────────────────────────────────────────────

// Read the machine's topology. Call once, after the PMM is up (the node tables
// are sized from its page count) and after the higher half is mapped (the ACPI
// tables are read through it), and before smp brings the other CPUs up.
pub fn initialise() {
	// A device tree is Vinix's native aarch64 description and is already parsed
	// by the time this runs; ACPI is what a UEFI machine provides. Try the one
	// that costs nothing to look at first.
	mut found := discover_devicetree()
	if found > 0 {
		numa_source = source_devicetree
	} else {
		found = discover_acpi()
		if found > 0 {
			numa_source = source_acpi
		}
	}

	if found < 1 {
		single_node()
		numa_source = source_none
	}

	fill_missing_distances()
	numa_multinode = numa_node_count > 1
	publish_to_pmm()
	report()
}

// Every machine has a node zero owning everything, so that a caller can ask
// the same questions of any board and get a truthful answer.
fn single_node() {
	numa_node_count = 1
	numa_hw_count = 0
	numa_nodes[0].present = true
	numa_nodes[0].domain = 0
	numa_nodes[0].range_count = 1
	numa_nodes[0].range_base[0] = 0
	numa_nodes[0].range_size[0] = memory.pmm_page_count() * page_size
}

// Firmware need not publish a full matrix; a SLIT is optional and a device
// tree distance-map lists only the pairs it cares about. Fill in the rest with
// the conventional values so callers never see a zero.
fn fill_missing_distances() {
	for a := 0; a < numa_node_count; a++ {
		for b := 0; b < numa_node_count; b++ {
			if numa_distances[a * max_nodes + b] != undeclared_distance {
				continue
			}
			numa_distances[a * max_nodes + b] = if a == b {
				local_distance
			} else {
				default_remote_distance
			}
		}
	}
}

// Hand the memory layout to the allocator and build each node's fallback order.
fn publish_to_pmm() {
	if !numa_multinode {
		return
	}
	for id := 0; id < numa_node_count; id++ {
		for r := 0; r < numa_nodes[id].range_count; r++ {
			memory.pmm_register_node_range(id, numa_nodes[id].range_base[r], numa_nodes[id].range_size[r])
		}
	}
	// Nearest first, itself included, so a node that runs out reaches for the
	// closest memory next instead of whatever the global scan walks into.
	for id := 0; id < numa_node_count; id++ {
		mut taken := u64(0)
		for step := 0; step < numa_node_count; step++ {
			mut best := -1
			for candidate := 0; candidate < numa_node_count; candidate++ {
				if taken & (u64(1) << u64(candidate)) != 0 {
					continue
				}
				if best < 0 || distance(id, candidate) < distance(id, best) {
					best = candidate
				}
			}
			if best < 0 {
				break
			}
			taken |= u64(1) << u64(best)
			memory.pmm_add_node_fallback(id, best)
		}
	}
	memory.pmm_enable_numa(numa_node_count)
}

// Record a node under the firmware's own name for it, returning the dense id
// this kernel will use. Called by both discovery paths.
fn intern_domain(domain u32) int {
	for id := 0; id < numa_node_count; id++ {
		if numa_nodes[id].present && numa_nodes[id].domain == domain {
			return id
		}
	}
	if numa_node_count == max_nodes {
		return no_node
	}
	id := numa_node_count
	numa_nodes[id].present = true
	numa_nodes[id].domain = domain
	numa_nodes[id].cpu_mask = 0
	numa_nodes[id].range_count = 0
	numa_node_count++
	return id
}

fn add_node_range(id int, base u64, length u64) {
	if id < 0 || id >= numa_node_count || length == 0 {
		return
	}
	if numa_nodes[id].range_count == max_node_ranges {
		return
	}
	index := numa_nodes[id].range_count
	numa_nodes[id].range_base[index] = base
	numa_nodes[id].range_size[index] = length
	numa_nodes[id].range_count++
}

fn add_hw_cpu(hw_id u64, id int) {
	if id < 0 || numa_hw_count == max_cpu_slots {
		return
	}
	for i := 0; i < numa_hw_count; i++ {
		if numa_hw_ids[i] == hw_id {
			numa_hw_nodes[i] = id
			return
		}
	}
	numa_hw_ids[numa_hw_count] = hw_id
	numa_hw_nodes[numa_hw_count] = id
	numa_hw_count++
}

// The dense id firmware's own name for a node maps to, or -1 when it never
// declared one. A distance that mentions a domain nothing was placed in is
// ignored rather than interned as a node of its own.
fn node_of_domain(domain u32) int {
	for id := 0; id < numa_node_count; id++ {
		if numa_nodes[id].present && numa_nodes[id].domain == domain {
			return id
		}
	}
	return no_node
}

fn set_distance(a int, b int, value u8) {
	if a < 0 || a >= max_nodes || b < 0 || b >= max_nodes || value == undeclared_distance {
		return
	}
	numa_distances[a * max_nodes + b] = value
}

// ── Attaching the CPUs ───────────────────────────────────────────────────────

// Give every logical CPU its node. Call once smp has numbered them: firmware
// names a CPU by its LAPIC id or its MPIDR, and only smp knows which logical
// number went to which of those.
pub fn attach_cpus() {
	count := cpu_local_count()
	for i := 0; i < count; i++ {
		mut node := node_for_hw_id(cpu_local_hw_id(i))
		if node < 0 {
			// A CPU firmware did not place belongs to node zero, which on a
			// machine with no topology is the whole machine anyway.
			node = 0
		}
		if i < max_cpu_slots {
			numa_cpu_nodes[i] = node
		}
		if node < numa_node_count && i < 64 {
			numa_nodes[node].cpu_mask |= u64(1) << u64(i)
		}
		set_cpu_local_node(i, node)
	}

	if !numa_multinode {
		return
	}
	for id := 0; id < numa_node_count; id++ {
		megabytes := memory.pmm_node_total_pages(id) * page_size / (1024 * 1024)
		println('numa: node ${id} holds cpus 0x${numa_nodes[id].cpu_mask:x} and ${megabytes} MiB')
	}
}

fn node_for_hw_id(hw_id u64) int {
	for i := 0; i < numa_hw_count; i++ {
		if numa_hw_ids[i] == hw_id {
			return numa_hw_nodes[i]
		}
	}
	return no_node
}

// ── What the rest of the kernel asks ────────────────────────────────────────

pub fn available() bool {
	return numa_multinode
}

pub fn node_count() int {
	return if numa_node_count > 0 { numa_node_count } else { 1 }
}

pub fn node_present(node int) bool {
	return node >= 0 && node < numa_node_count && numa_nodes[node].present
}

pub fn node_domain(node int) u32 {
	if !node_present(node) {
		return 0
	}
	return numa_nodes[node].domain
}

pub fn node_cpu_mask(node int) u64 {
	if !node_present(node) {
		return 0
	}
	return numa_nodes[node].cpu_mask
}

pub fn source() string {
	return match numa_source {
		source_devicetree { 'device tree' }
		source_acpi { 'acpi' }
		else { 'none' }
	}
}

pub fn distance(a int, b int) u8 {
	if a < 0 || a >= max_nodes || b < 0 || b >= max_nodes {
		return default_remote_distance
	}
	value := numa_distances[a * max_nodes + b]
	if value == undeclared_distance {
		return if a == b { local_distance } else { default_remote_distance }
	}
	return value
}

// How many logical CPUs the machine brought up. Reported here so that a reader
// outside the architecture modules does not have to reach into cpu_locals.
pub fn cpu_count() int {
	return cpu_local_count()
}

pub fn node_of_cpu(cpu_number int) int {
	if cpu_number < 0 || cpu_number >= max_cpu_slots {
		return 0
	}
	return numa_cpu_nodes[cpu_number]
}

// The node of the CPU this code is running on. Read without disabling
// interrupts: a migration between the read and its use turns an exact answer
// into a slightly stale preference, which is all any caller wants it for.
pub fn current_node() int {
	if !numa_multinode {
		return 0
	}
	number := current_cpu_number()
	if number < 0 || number >= max_cpu_slots {
		return 0
	}
	return numa_cpu_nodes[number]
}

// A mask of every node that exists, which is what get_mempolicy(2) reports for
// MPOL_F_MEMS_ALLOWED.
pub fn all_nodes_mask() u64 {
	mut mask := u64(0)
	for id := 0; id < numa_node_count && id < 64; id++ {
		mask |= u64(1) << u64(id)
	}
	return mask
}

// ── Memory policy ───────────────────────────────────────────────────────────

// Where the current thread's next anonymous page should come from, and whether
// that is a requirement or a preference. Linux's first-touch rule is the
// default: the page comes from the node the faulting thread is running on.
fn preferred_node() (int, bool) {
	if !numa_multinode {
		return no_node, false
	}
	home := current_node()

	running := proc.current_thread()
	if running == unsafe { nil } {
		return home, false
	}
	mut process := running.process
	if process == unsafe { nil } {
		return home, false
	}

	mask := process.mempolicy_nodemask & all_nodes_mask()
	match process.mempolicy_mode {
		mpol_bind {
			if mask == 0 {
				return home, false
			}
			// Staying put satisfies the binding whenever it is allowed to.
			if mask & (u64(1) << u64(home)) != 0 {
				return home, true
			}
			return first_node_in(mask), true
		}
		mpol_preferred {
			if mask == 0 {
				return home, false
			}
			if mask & (u64(1) << u64(home)) != 0 {
				return home, false
			}
			return first_node_in(mask), false
		}
		mpol_interleave {
			if mask == 0 {
				return home, false
			}
			return interleave_next(mut process, mask), false
		}
		else {
			// MPOL_DEFAULT and MPOL_LOCAL both mean "the node I am on".
			return home, false
		}
	}
}

fn first_node_in(mask u64) int {
	for id := 0; id < numa_node_count && id < 64; id++ {
		if mask & (u64(1) << u64(id)) != 0 {
			return id
		}
	}
	return 0
}

// Round-robin across the policy's nodes. The cursor lives on the process, so
// its threads interleave together rather than each starting over. It is read
// and written without a lock: two threads faulting at once may take the same
// node, which costs an interleave one step of its rotation and nothing else.
fn interleave_next(mut process proc.Process, mask u64) int {
	for step := 0; step < numa_node_count && step < 64; step++ {
		candidate := int((process.mempolicy_interleave + u64(step)) % u64(numa_node_count))
		if mask & (u64(1) << u64(candidate)) != 0 {
			process.mempolicy_interleave = u64(candidate + 1) % u64(numa_node_count)
			return candidate
		}
	}
	return first_node_in(mask)
}

// A page for the current thread's address space, honouring its memory policy.
// Returns nil on exhaustion, like the fallible PMM entry points it wraps: the
// caller is serving a userspace fault and can report ENOMEM.
pub fn alloc_user_page() voidptr {
	if !numa_multinode {
		return memory.pmm_alloc_fallible(1)
	}
	node, strict := preferred_node()
	if node < 0 {
		return memory.pmm_alloc_fallible(1)
	}
	return memory.pmm_alloc_on_node(1, node, strict)
}

pub fn alloc_user_page_nozero() voidptr {
	if !numa_multinode {
		return memory.pmm_alloc_nozero_fallible(1)
	}
	node, strict := preferred_node()
	if node < 0 {
		return memory.pmm_alloc_nozero_fallible(1)
	}
	return memory.pmm_alloc_nozero_on_node(1, node, strict)
}

// ── Syscalls ────────────────────────────────────────────────────────────────

// getcpu(cpu, node, tcache). Both pointers are optional, as on Linux.
pub fn syscall_getcpu(_ voidptr, cpu_ptr u64, node_ptr u64, _tcache u64) (u64, u64) {
	number := current_cpu_number()
	cpu_number := u32(if number < 0 { 0 } else { number })
	node := u32(node_of_cpu(int(cpu_number)))
	if cpu_ptr != 0 && !usercopy.copy_to_user(cpu_ptr, voidptr(&cpu_number), sizeof(u32)) {
		return errno.err, errno.efault
	}
	if node_ptr != 0 && !usercopy.copy_to_user(node_ptr, voidptr(&node), sizeof(u32)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// The largest nodemask a caller may name. Linux's own limit is MAX_NUMNODES,
// and one is needed here for the same reason: the bit count decides how many
// words are copied, so an unbounded one is an unbounded loop over user memory.
const max_nodemask_bits = u64(8 * 1024)

// Read a Linux nodemask. `maxnode` counts bits, not words, and zero means "no
// mask at all". Vinix supports sixteen nodes, so one word is always enough;
// bits above that must be clear or the request names a node which cannot exist.
fn read_nodemask(nodemask u64, maxnode u64) ?u64 {
	if nodemask == 0 || maxnode == 0 {
		return u64(0)
	}
	if maxnode > max_nodemask_bits {
		return none
	}
	words := (maxnode + 63) / 64
	mut mask := u64(0)
	for word := u64(0); word < words; word++ {
		mut value := u64(0)
		if !usercopy.copy_from_user(voidptr(&value), nodemask + word * 8, sizeof(u64)) {
			return none
		}
		if word == 0 {
			mask = value
		} else if value != 0 {
			return none
		}
	}
	// Bits past the caller's own maxnode are not part of the mask.
	if maxnode < 64 {
		mask &= (u64(1) << maxnode) - 1
	}
	return mask
}

fn store_policy(mut process proc.Process, mode int, mask u64) (u64, u64) {
	// A mode that needs nodes and was given none is the caller's mistake, not
	// something to guess at.
	if mode == mpol_bind || mode == mpol_interleave {
		if mask == 0 {
			return errno.err, errno.einval
		}
	}
	if (mask & ~all_nodes_mask()) != 0 {
		return errno.err, errno.einval
	}
	process.mempolicy_mode = mode
	process.mempolicy_nodemask = mask
	process.mempolicy_interleave = 0
	return 0, 0
}

// set_mempolicy(mode, nodemask, maxnode). The policy is process-wide and is
// inherited by a fork, as on Linux.
pub fn syscall_set_mempolicy(_ voidptr, mode int, nodemask u64, maxnode u64) (u64, u64) {
	if mode < 0 || mode >= mpol_max {
		return errno.err, errno.einval
	}
	mask := read_nodemask(nodemask, maxnode) or { return errno.err, errno.einval }

	mut running := proc.current_thread()
	if running == unsafe { nil } {
		return errno.err, errno.einval
	}
	mut process := running.process
	if process == unsafe { nil } {
		return errno.err, errno.einval
	}
	if mode == mpol_default || mode == mpol_local {
		process.mempolicy_mode = mode
		process.mempolicy_nodemask = 0
		process.mempolicy_interleave = 0
		return 0, 0
	}
	return store_policy(mut process, mode, mask)
}

// get_mempolicy(mode, nodemask, maxnode, addr, flags).
pub fn syscall_get_mempolicy(_ voidptr, mode_ptr u64, nodemask u64, maxnode u64, _addr u64, flags u64) (u64, u64) {
	mut running := proc.current_thread()
	if running == unsafe { nil } {
		return errno.err, errno.einval
	}
	process := running.process
	if process == unsafe { nil } {
		return errno.err, errno.einval
	}
	if (flags & ~u64(mpol_f_node | mpol_f_addr | mpol_f_mems_allowed)) != 0 {
		return errno.err, errno.einval
	}

	mut reported_mode := process.mempolicy_mode
	mut reported_mask := process.mempolicy_nodemask
	if (flags & u64(mpol_f_mems_allowed)) != 0 {
		// MPOL_F_MEMS_ALLOWED asks which nodes the caller may use at all, and
		// is defined to reject the flags that ask about a policy instead.
		if (flags & u64(mpol_f_node | mpol_f_addr)) != 0 {
			return errno.err, errno.einval
		}
		reported_mask = all_nodes_mask()
	} else if (flags & u64(mpol_f_node)) != 0 {
		// With MPOL_F_NODE and no address, `mode` receives the node the caller
		// is running on rather than its policy.
		reported_mode = current_node()
	}

	if mode_ptr != 0 {
		value := int(reported_mode)
		if !usercopy.copy_to_user(mode_ptr, voidptr(&value), sizeof(int)) {
			return errno.err, errno.efault
		}
	}
	if nodemask != 0 {
		if maxnode == 0 || maxnode > max_nodemask_bits {
			return errno.err, errno.einval
		}
		words := (maxnode + 63) / 64
		for word := u64(0); word < words; word++ {
			value := if word == 0 { reported_mask } else { u64(0) }
			if !usercopy.copy_to_user(nodemask + word * 8, voidptr(&value), sizeof(u64)) {
				return errno.err, errno.efault
			}
		}
	}
	return 0, 0
}

// mbind(addr, len, mode, nodemask, maxnode, flags).
//
// Vinix has no per-range policy store, so a binding applies to the process the
// way set_mempolicy(2) does. That is weaker than Linux, and deliberately so: a
// caller that binds one arena and then faults it in gets its pages from the
// nodes it asked for, which is the effect programs use mbind for. Pages already
// faulted in are not moved, exactly as on Linux without MPOL_MF_MOVE.
pub fn syscall_mbind(_ voidptr, addr u64, _length u64, mode int, nodemask u64, maxnode u64, _flags u64) (u64, u64) {
	if (addr & (page_size - 1)) != 0 {
		return errno.err, errno.einval
	}
	if mode < 0 || mode >= mpol_max {
		return errno.err, errno.einval
	}
	mask := read_nodemask(nodemask, maxnode) or { return errno.err, errno.einval }

	mut running := proc.current_thread()
	if running == unsafe { nil } {
		return errno.err, errno.einval
	}
	mut process := running.process
	if process == unsafe { nil } {
		return errno.err, errno.einval
	}
	if mode == mpol_default || mode == mpol_local {
		process.mempolicy_mode = mode
		process.mempolicy_nodemask = 0
		process.mempolicy_interleave = 0
		return 0, 0
	}
	return store_policy(mut process, mode, mask)
}

// ── Reporting ───────────────────────────────────────────────────────────────

fn report() {
	if !numa_multinode {
		println('numa: one memory node (${source()})')
		return
	}
	println('numa: ${numa_node_count} memory nodes from ${source()}')
	for id := 0; id < numa_node_count; id++ {
		for r := 0; r < numa_nodes[id].range_count; r++ {
			base := numa_nodes[id].range_base[r]
			size := numa_nodes[id].range_size[r]
			println('numa:   node ${id} memory 0x${base:x}-0x${base + size:x}')
		}
	}
	for a := 0; a < numa_node_count; a++ {
		mut line := 'numa:   node ${a} distances'
		for b := 0; b < numa_node_count; b++ {
			line += ' ${distance(a, b)}'
		}
		println(line)
	}
}
