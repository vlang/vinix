// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// AArch64 topology discovery and the per-CPU hooks the core module needs.
//
// A device tree names a CPU by the affinity bits of its MPIDR and places it
// with a `numa-node-id` property; memory is placed the same way, one
// `memory@...` node per range. That is the binding Linux documents in
// Documentation/devicetree/bindings/numa.txt, and what QEMU's virt machine
// emits when it boots without UEFI.
@[has_globals]
module numa

import devicetree
import limine
import aarch64.cpu
import aarch64.cpu.local as cpulocal

// A machine booted through UEFI has ACPI tables and no device tree, which is
// what the aarch64 QEMU machine is. The amd64 build reuses the acpi module's
// request instead of asking for a second copy of the same pointer.
@[_linker_section: '.requests']
@[cinit]
__global (
	volatile numa_rsdp_req = limine.LimineRSDPRequest{
		response: unsafe { nil }
	}
)

fn acpi_rsdp_address() u64 {
	if numa_rsdp_req.response == unsafe { nil } {
		return 0
	}
	return u64(numa_rsdp_req.response.address)
}

// Read /cpus and the memory nodes. Returns the number of nodes found, or zero
// when this machine has no device tree or the tree says nothing about NUMA.
fn discover_devicetree() int {
	if !devicetree.is_available() {
		return 0
	}
	cpus := devicetree.find_node('/cpus') or { return 0 }

	// How many cells name a CPU. Almost always one; a big machine that needs
	// Aff3 uses two.
	address_cells := devicetree.get_u32(cpus, '#address-cells') or { u32(1) }

	mut placed_cpus := 0
	for child in cpus.children {
		domain := devicetree.get_u32(child, 'numa-node-id') or { continue }
		cells := devicetree.get_u32_array(child, 'reg') or { continue }
		if cells.len == 0 {
			unsafe { cells.free() }
			continue
		}
		hw_id := if address_cells >= 2 && cells.len >= 2 {
			((u64(cells[0]) << 32) | u64(cells[1])) & mpidr_affinity_mask
		} else {
			u64(cells[0]) & mpidr_affinity_mask
		}
		unsafe { cells.free() }

		id := intern_domain(domain)
		if id < 0 {
			continue
		}
		add_hw_cpu(hw_id, id)
		placed_cpus++
	}

	root := devicetree.find_node('/') or { return 0 }
	mut placed_ranges := 0
	for child in root.children {
		if !child.name.starts_with('memory') {
			continue
		}
		domain := devicetree.get_u32(child, 'numa-node-id') or { continue }
		regs := devicetree.get_reg(child) or { continue }
		id := intern_domain(domain)
		if id >= 0 {
			for i := 0; i + 1 < regs.len; i += 2 {
				add_node_range(id, regs[i], regs[i + 1])
				placed_ranges++
			}
		}
		unsafe { regs.free() }
	}

	if placed_cpus == 0 && placed_ranges == 0 {
		// Nothing was placed, so whatever nodes were interned describe nothing.
		numa_node_count = 0
		numa_hw_count = 0
		return 0
	}

	read_devicetree_distances()
	return numa_node_count
}

// /distance-map holds triplets of (source, destination, distance). Firmware
// lists only the pairs it has something to say about; the core module fills in
// the rest.
fn read_devicetree_distances() {
	map_node := devicetree.find_compatible('numa-distance-map-v1') or { return }
	matrix := devicetree.get_u32_array(map_node, 'distance-matrix') or { return }
	defer {
		unsafe { matrix.free() }
	}
	for i := 0; i + 2 < matrix.len; i += 3 {
		a := node_of_domain(matrix[i])
		b := node_of_domain(matrix[i + 1])
		value := matrix[i + 2]
		if a < 0 || b < 0 || value == 0 || value > 254 {
			continue
		}
		set_distance(a, b, u8(value))
	}
}

// ── Per-CPU hooks ───────────────────────────────────────────────────────────

fn cpu_local_count() int {
	return cpu_locals.len
}

fn cpu_local_at(cpu_number int) &cpulocal.Local {
	if cpu_number < 0 || cpu_number >= cpu_locals.len {
		return unsafe { nil }
	}
	return cpu_locals[cpu_number]
}

fn cpu_local_hw_id(cpu_number int) u64 {
	entry := cpu_local_at(cpu_number)
	if entry == unsafe { nil } {
		return 0
	}
	return entry.mpidr & mpidr_affinity_mask
}

fn set_cpu_local_node(cpu_number int, node int) {
	mut entry := cpu_local_at(cpu_number)
	if entry == unsafe { nil } {
		return
	}
	entry.numa_node = u32(node)
}

fn current_cpu_number() int {
	if cpu_locals.len == 0 {
		return 0
	}
	number := int(cpu.read_tpidr_el1())
	if number < 0 || number >= cpu_locals.len {
		return 0
	}
	return number
}
