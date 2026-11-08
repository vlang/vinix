// SPDX-License-Identifier: GPL-2.0-or-later
module pages

// One ownership bit per 4 KiB frame over the complete PPC32 address space.
// Initialisation starts reserved; only firmware-advertised free RAM is added.
// Callers serialize allocation (the initial kernel is single-CPU, IRQ-off).
pub struct Pool {
mut:
	free  [32768]u32
	owned [32768]u32
pub mut:
	count u32
}

pub fn (mut pool Pool) add(base u32, size u32) bool {
	end := u64(base) + size
	if end > u64(1) << 32 { return false }
	start_frame := if base == 0 { u64(1) } else { (u64(base) + 4095) >> 12 }
	end_frame := end >> 12
	for frame := start_frame; frame < end_frame; frame++ {
		word := u32(frame >> 5)
		mask := u32(1) << u32(frame & 31)
		if pool.owned[word] & mask != 0 { return false }
	}
	for frame := start_frame; frame < end_frame; frame++ {
		word := u32(frame >> 5)
		mask := u32(1) << u32(frame & 31)
		if pool.free[word] & mask == 0 {
			pool.free[word] |= mask
			pool.count++
		}
	}
	return true
}

pub fn (mut pool Pool) take(count u32, alignment u32) u32 {
	if count == 0 || count > pool.count || alignment == 0 || alignment & (alignment - 1) != 0
		|| alignment > 0x100000 {
		return 0
	}
	// Never allocate frame zero: a zero return denotes exhaustion.
	mut first := alignment
	for first <= 0x100000 - count {
		mut available := u32(0)
		for available < count {
			frame := first + available
			if pool.free[frame >> 5] & (u32(1) << (frame & 31)) == 0 { break }
			available++
		}
		if available == count {
			for frame := first; frame < first + count; frame++ {
				mask := u32(1) << (frame & 31)
				pool.free[frame >> 5] &= ~mask
				pool.owned[frame >> 5] |= mask
			}
			pool.count -= count
			return first << 12
		}
		first = (first + available + alignment) & ~(alignment - 1)
	}
	return 0
}

pub fn (mut pool Pool) give(base u32, count u32) bool {
	first := base >> 12
	if base & 4095 != 0 || first == 0 || count == 0 || count > 0x100000 - first { return false }
	for frame := first; frame < first + count; frame++ {
		if pool.owned[frame >> 5] & (u32(1) << (frame & 31)) == 0 { return false }
	}
	for frame := first; frame < first + count; frame++ {
		mask := u32(1) << (frame & 31)
		pool.owned[frame >> 5] &= ~mask
		pool.free[frame >> 5] |= mask
	}
	pool.count += count
	return true
}
