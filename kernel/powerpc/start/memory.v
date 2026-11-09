// SPDX-License-Identifier: GPL-2.0-or-later
module main

import powerpc.runtime

__global process_break_min u32
__global process_break u32

const anonymous_start = u32(0x52000000)
const anonymous_end = u32(0x57000000)

// These ranges belong only to anonymous RAM. The ELF, stack and framebuffer
// cannot be freed through this path, even with a forged munmap address.
fn release_ram(begin u32, end u32) {
	for address := begin; address < end; address += 4096 {
		physical := user_space.translate(address, false)
		if physical == 0 { continue }
		if !user_space.unmap(address) || !physical_pages.give(physical, 1) { halt(c'anonymous page ownership') }
	}
}

fn allocate_ram(begin u32, end u32) bool {
	for address := begin; address < end; address += 4096 {
		physical := physical_pages.take(1, 1)
		if physical == 0 { release_ram(begin, address); return false }
		runtime.fill(voidptr(physical), 0, 4096)
		if !user_space.map(address, physical, true) {
			physical_pages.give(physical, 1)
			release_ram(begin, address)
			return false
		}
	}
	return true
}

fn sys_brk(address u32) int {
	if address < process_break_min || address >= anonymous_start { return int(process_break) }
	old_end := (process_break + 4095) & ~u32(4095)
	new_end := (address + 4095) & ~u32(4095)
	if new_end > old_end && !allocate_ram(old_end, new_end) { return int(process_break) }
	if new_end < old_end { release_ram(new_end, old_end) }
	process_break = address
	return int(address)
}

fn anonymous_map(address u32, length u32, protection u32, flags u32, offset u32) int {
	// Fixed remapping, executable memory and shared mappings need VMA ownership
	// and process sharing first. Do not silently accept those flags.
	if length == 0 || length > anonymous_end - anonymous_start || protection != 3
		|| flags != 0x22 || offset != 0 { return -22 }
	size := (length + 4095) & ~u32(4095)
	mut begin := anonymous_start
	if address >= anonymous_start && address < anonymous_end && address & 4095 == 0 {
		begin = address
	}
	for pass in 0 .. 2 {
		limit := if pass == 0 { anonymous_end } else { begin }
		mut candidate := if pass == 0 { begin } else { anonymous_start }
		for candidate <= limit - size {
			mut used := u32(0)
			for used < size && user_space.translate(candidate + used, false) == 0 { used += 4096 }
			if used == size {
				if !allocate_ram(candidate, candidate + size) { return -12 }
				return int(candidate)
			}
			candidate += used + 4096
		}
	}
	return -12
}

fn anonymous_unmap(address u32, length u32) int {
	if address & 4095 != 0 || address < anonymous_start || address >= anonymous_end
		|| length == 0 || length > anonymous_end - address { return -22 }
	release_ram(address, address + ((length + 4095) & ~u32(4095)))
	return 0
}
