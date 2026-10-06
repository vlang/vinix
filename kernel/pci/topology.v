// SPDX-License-Identifier: GPL-2.0-only
module pci

import memory

// This callback completes one checked, read-only domain-zero transaction.
// BDF is (bus << 8) | (slot << 3) | function; widths are bytes. Native V int
// is used deliberately: the callback and its tuple are not a C PCI ABI.
pub type TopologyRead = fn (u32, u16, u8) (u32, int)

pub const topology_ok = 0
pub const topology_not_ready = -11
pub const topology_no_memory = -12
pub const topology_invalid = -22
pub const topology_cycle = -40
pub const topology_io_error = -5
pub const topology_malformed = -71

// These are native boot observations, not Linux pci_bus/pci_dev objects.
// Graph pointers are borrowed until the uniquely owned Topology is destroyed.
pub struct TopologyBus {
pub:
	number            u8
	root_number       u8
	parent            &TopologyBus = unsafe { nil }
	parent_bridge_bdf i32          = -1
	// Root 255 is a traversal bound, not a claimed host resource window.
	subordinate_limit u8
mut:
	next &TopologyBus = unsafe { nil }
}

pub struct TopologyFunction {
pub:
	bdf                u32
	identity           u32
	class_revision     u32
	header_type        u8
	multifunction      bool
	irq_pin            u8
	subsystem_identity u32
	has_subsystem      bool
	bus                &TopologyBus = unsafe { nil }
	parent_bridge_bdf  i32          = -1
	bridge_primary     u8
	bridge_secondary   u8
	bridge_subordinate u8
mut:
	next &TopologyFunction = unsafe { nil }
}

// No callback or caller's root storage is retained. Only the header, one
// record per visited bus and one record per present function are allocated.
// Mutable native PCIDevice objects and capability bitmaps belong to the boot
// publisher, outside private snapshots.
pub struct Topology {
mut:
	buses_first         &TopologyBus      = unsafe { nil }
	buses_last          &TopologyBus      = unsafe { nil }
	functions_first     &TopologyFunction = unsafe { nil }
	functions_last      &TopologyFunction = unsafe { nil }
	bus_length          u32
	function_length     u32
	seen_buses          [4]u64
	allocation_attempts u32
	fail_after          u32
}

pub fn (snapshot &Topology) first_bus() &TopologyBus {
	if snapshot == unsafe { nil } { return unsafe { nil } }
	return snapshot.buses_first
}

pub fn (snapshot &Topology) first_function() &TopologyFunction {
	if snapshot == unsafe { nil } { return unsafe { nil } }
	return snapshot.functions_first
}

pub fn (snapshot &Topology) bus_count() u32 {
	if snapshot == unsafe { nil } { return 0 }
	return snapshot.bus_length
}

pub fn (snapshot &Topology) function_count() u32 {
	if snapshot == unsafe { nil } { return 0 }
	return snapshot.function_length
}

pub fn (bus &TopologyBus) next_bus() &TopologyBus {
	if bus == unsafe { nil } { return unsafe { nil } }
	return bus.next
}

pub fn (device &TopologyFunction) next_function() &TopologyFunction {
	if device == unsafe { nil } { return unsafe { nil } }
	return device.next
}

fn (snapshot &Topology) bus_seen(number u8) bool {
	return snapshot.seen_buses[number >> 6] & (u64(1) << (number & 63)) != 0
}

fn (mut snapshot Topology) allocate(size u64) voidptr {
	// At most 1 + 256 buses + 65536 functions, so this cannot wrap.
	snapshot.allocation_attempts++
	if snapshot.fail_after != 0 && snapshot.allocation_attempts == snapshot.fail_after {
		return unsafe { nil }
	}
	return memory.malloc_packed_fallible(size)
}

fn (mut snapshot Topology) append_bus(number u8, root_number u8,
	parent &TopologyBus, parent_bdf i32, limit u8) int {
	mut node := unsafe { &TopologyBus(snapshot.allocate(sizeof(TopologyBus))) } @[freed]
	if node == unsafe { nil } { return topology_no_memory }
	unsafe {
		*node = TopologyBus{
			number:            number
			root_number:       root_number
			parent:            parent
			parent_bridge_bdf: parent_bdf
			subordinate_limit: limit
		}
	}
	if snapshot.buses_last == unsafe { nil } {
		snapshot.buses_first = node
	} else {
		snapshot.buses_last.next = node
	}
	snapshot.buses_last = node
	snapshot.bus_length++
	snapshot.seen_buses[number >> 6] |= u64(1) << (number & 63)
	return topology_ok
}

fn topology_is_ancestor(ancestor &TopologyBus, descendant &TopologyBus) bool {
	// Both pointers belong to this live, privately owned graph.
	mut node := unsafe { descendant }
	for node != unsafe { nil } {
		if voidptr(node) == voidptr(ancestor) { return true }
		node = node.parent
	}
	return false
}

fn (snapshot &Topology) child_status(bus &TopologyBus, primary u8,
	secondary u8, subordinate u8) int {
	// An unconfigured bridge remains an observed function; no bus is invented.
	if secondary == 0 && subordinate == 0 { return topology_ok }
	if primary != bus.number || secondary == 0 || secondary > subordinate
		|| subordinate > bus.subordinate_limit {
		return topology_malformed
	}
	if snapshot.bus_seen(secondary) { return topology_cycle }
	if secondary <= bus.number { return topology_malformed }

	mut other := snapshot.buses_first
	for other != unsafe { nil } {
		if other.parent == unsafe { nil } {
			// Roots are all reserved before any bridge is traversed.
			if other.number >= secondary && other.number <= subordinate {
				return topology_cycle
			}
		} else if secondary <= other.subordinate_limit && other.number <= subordinate {
			// Nested windows are expected; intersecting siblings/other roots
			// cannot both own the same conventional domain-zero bus numbers.
			if !topology_is_ancestor(other, bus) { return topology_malformed }
		}
		other = other.next
	}
	return topology_ok
}

fn (mut snapshot Topology) scan_function(bus &TopologyBus, bdf u32,
	topology_reader TopologyRead) int {
	identity, identity_status := topology_reader(bdf, 0, 4)
	if identity_status != 0 { return topology_io_error }
	// Match genuine empty responses, including a vendor-only all-ones read.
	if u16(identity) == 0xffff || identity == 0 || identity == 0xffff0000 {
		return topology_ok
	}
	// CRS needs a real retry/wait policy. Early boot cannot borrow task waits.
	if u16(identity) == 0x0001 { return topology_not_ready }

	class_revision, class_status := topology_reader(bdf, 0x08, 4)
	if class_status != 0 { return topology_io_error }
	header, header_status := topology_reader(bdf, 0x0c, 4)
	if header_status != 0 { return topology_io_error }
	header_byte := u8(header >> 16)
	header_type := header_byte & 0x7f
	class_subclass := u16(class_revision >> 16)
	if header_type > 2 || (header_type == 1 && class_subclass != 0x0604)
		|| (header_type == 2 && class_subclass != 0x0607)
		|| (header_type == 0 && (class_subclass == 0x0604 || class_subclass == 0x0607)) {
		return topology_malformed
	}
	interrupt, interrupt_status := topology_reader(bdf, 0x3c, 4)
	if interrupt_status != 0 { return topology_io_error }

	mut subsystem := u32(0)
	if header_type == 0 || header_type == 2 {
		subsystem_offset := if header_type == 0 { u16(0x2c) } else { u16(0x40) }
		value, status := topology_reader(bdf, subsystem_offset, 4)
		if status != 0 { return topology_io_error }
		subsystem = value
	}
	mut primary := u8(0)
	mut secondary := u8(0)
	mut subordinate := u8(0)
	if header_type == 1 || header_type == 2 {
		value, status := topology_reader(bdf, 0x18, 4)
		if status != 0 { return topology_io_error }
		primary = u8(value)
		secondary = u8(value >> 8)
		subordinate = u8(value >> 16)
		child_status := snapshot.child_status(bus, primary, secondary, subordinate)
		if child_status != topology_ok { return child_status }
	}

	mut node := unsafe { &TopologyFunction(snapshot.allocate(sizeof(TopologyFunction))) } @[freed]
	if node == unsafe { nil } { return topology_no_memory }
	unsafe {
		*node = TopologyFunction{
			bdf:                bdf
			identity:           identity
			class_revision:     class_revision
			header_type:        header_type
			multifunction:      header_byte & 0x80 != 0
			irq_pin:            u8(interrupt >> 8)
			subsystem_identity: subsystem
			has_subsystem:      header_type == 0 || header_type == 2
			bus:                bus
			parent_bridge_bdf:  bus.parent_bridge_bdf
			bridge_primary:     primary
			bridge_secondary:   secondary
			bridge_subordinate: subordinate
		}
	}
	if snapshot.functions_last == unsafe { nil } {
		snapshot.functions_first = node
	} else {
		snapshot.functions_last.next = node
	}
	snapshot.functions_last = node
	snapshot.function_length++
	if secondary != 0 || subordinate != 0 {
		return snapshot.append_bus(secondary, bus.root_number, bus, i32(bdf), subordinate)
	}
	return topology_ok
}

// Roots are actual caller-supplied bus numbers, borrowed only during this
// call. The backend never infers a root bus from host function numbering.
// Every error returns nil after complete cleanup. fail_after=0 is normal;
// N rejects the Nth owned allocation attempt for deterministic rollback tests.
// Construction is for early boot or ordinary tasks, not IRQ/atomic context:
// the fallible native allocator can run reclaimers under memory pressure.
pub fn topology_build(roots &u8, root_count u32, topology_reader TopologyRead,
	fail_after u32) (&Topology, int) {
	if roots == unsafe { nil } || root_count == 0 || root_count > 256
		|| topology_reader == unsafe { nil } {
		return unsafe { nil }, topology_invalid
	}
	for i := u32(0); i < root_count; i++ {
		for j := u32(0); j < i; j++ {
			if unsafe { roots[i] == roots[j] } {
				return unsafe { nil }, topology_cycle
			}
		}
	}
	if fail_after == 1 { return unsafe { nil }, topology_no_memory }
	mut snapshot := unsafe { &Topology(memory.malloc_packed_fallible(sizeof(Topology))) } @[freed]
	if snapshot == unsafe { nil } { return unsafe { nil }, topology_no_memory }
	unsafe { *snapshot = Topology{ allocation_attempts: 1, fail_after: fail_after } }
	for i := u32(0); i < root_count; i++ {
		number := unsafe { roots[i] }
		status := snapshot.append_bus(number, number, unsafe { nil }, -1, 255)
		if status != topology_ok {
			topology_destroy(snapshot)
			return unsafe { nil }, status
		}
	}

	// Appended child buses form a FIFO worklist. No recursion or reallocating
	// buffer can invalidate a retained graph pointer or grow the kernel stack.
	mut bus := snapshot.buses_first
	for bus != unsafe { nil } {
		for devfn := u32(0); devfn < 256; devfn++ {
			// Preserve the native scanner's all-eight-functions behavior even
			// without function zero/multifunction. This is no ARI/quirk claim.
			bdf := (u32(bus.number) << 8) | devfn
			status := snapshot.scan_function(bus, bdf, topology_reader)
			if status != topology_ok {
				topology_destroy(snapshot)
				return unsafe { nil }, status
			}
		}
		bus = bus.next
	}
	return snapshot, topology_ok
}

// The caller must stop all private readers before destroying their snapshot.
// Boot publication keeps its separate owner for the whole boot. nil is safe;
// a nonnil uniquely owned snapshot is destroyed exactly once.
pub fn topology_destroy(snapshot &Topology) {
	if snapshot == unsafe { nil } { return }
	mut device := snapshot.functions_first
	for device != unsafe { nil } {
		next := device.next
		memory.free(device)
		device = next
	}
	mut bus := snapshot.buses_first
	for bus != unsafe { nil } {
		next := bus.next
		memory.free(bus)
		bus = next
	}
	memory.free(snapshot)
}
