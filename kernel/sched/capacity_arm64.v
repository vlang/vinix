// SPDX-License-Identifier: GPL-2.0-or-later
module sched

import devicetree

// Standard DT CPU capacities are relative; normalize against the largest.
// Match firmware CPU reg cells to MPIDR, never to enumeration order.
fn configure_cpu_capacities() {
	cpus := devicetree.find_node('/cpus') or { return }
	mut largest := u32(0)
	for node in cpus.children {
		value := devicetree.get_u32(node, 'capacity-dmips-mhz') or { continue }
		if value > largest { largest = value }
	}
	if largest == 0 { return }
	for node in cpus.children {
		value := devicetree.get_u32(node, 'capacity-dmips-mhz') or { continue }
		reg := devicetree.get_reg(node) or { continue }
		if reg.len == 0 {
			unsafe { reg.free() }
			continue
		}
		mpidr := reg[0]
		unsafe { reg.free() }
		capacity := u32(u64(value) * 1024 / u64(largest))
		for entry in cpu_locals {
			if entry.mpidr & u64(0xff00ffffff) == mpidr & u64(0xff00ffffff) {
				set_cpu_capacity(entry.cpu_number, if capacity == 0 { u32(1) } else { capacity })
			}
		}
	}
}
