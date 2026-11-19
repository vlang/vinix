// SPDX-License-Identifier: GPL-2.0-or-later
module gem

// Backing accessors. Callers must not add an offset to phys_addr or virt_addr
// themselves: an object is either one physical run (phys_addr) or a list of
// single pages (pages), and these are the only places that know which.

// The physical address of byte `offset`, or none past the end or without
// backing.
pub fn (obj &GemObject) page_phys(offset u64) ?u64 {
	if obj == unsafe { nil } || offset >= obj.size { return none }
	if obj.pages != unsafe { nil } {
		return unsafe { obj.pages[offset / page_size] } + offset % page_size
	}
	if obj.phys_addr == 0 { return none }
	return obj.phys_addr + offset
}

// The physically contiguous run that starts at `offset` and is at most
// `length` bytes: its physical address and its length. Mapping a range walks
// these runs until it is covered. Adjacent pages of a scattered object merge
// into one run.
pub fn (obj &GemObject) contiguous_run(offset u64, length u64) ?(u64, u64) {
	if obj == unsafe { nil } || length == 0 || offset >= obj.size { return none }
	remaining := obj.size - offset
	run_limit := if length < remaining { length } else { remaining }
	if obj.pages != unsafe { nil } {
		mut page_index := offset / page_size
		run_start := unsafe { obj.pages[page_index] } + offset % page_size
		mut run_length := page_size - offset % page_size
		// While bytes remain below run_limit, the next page is inside the object.
		for run_length < run_limit
			&& unsafe { obj.pages[page_index + 1] == obj.pages[page_index] + page_size } {
			page_index++
			run_length += page_size
		}
		return run_start, if run_length < run_limit { run_length } else { run_limit }
	}
	if obj.phys_addr == 0 { return none }
	return obj.phys_addr + offset, run_limit
}

// The physical base of an object allocated as one run, for devices that need
// a single contiguous buffer, such as display scanout. A scattered object is
// refused even if its pages happen to be adjacent.
pub fn (obj &GemObject) contiguous_phys() ?u64 {
	if obj == unsafe { nil } || obj.pages != unsafe { nil } { return none }
	base, base_length := obj.contiguous_run(0, obj.size) or { return none }
	if base_length != obj.size { return none }
	return base
}

// Copy `length` bytes into the backing at `offset`: through the object's
// kernel mapping when it has one, otherwise through the direct map one run at
// a time. False if the range is outside the object.
pub fn (obj &GemObject) write_bytes(offset u64, data voidptr, length u64) bool {
	if obj == unsafe { nil } || offset > obj.size || length > obj.size - offset { return false }
	if obj.virt_addr != 0 {
		// One kernel mapping covers the object: a contiguous run in the direct
		// map, or a host aperture.
		unsafe { C.memcpy(voidptr(obj.virt_addr + offset), data, length) }
		return true
	}
	if obj.external { return false }
	mut copied := u64(0)
	for copied < length {
		run_phys, run_length := obj.contiguous_run(offset + copied, length - copied) or { return false }
		unsafe { C.memcpy(voidptr(run_phys + higher_half), voidptr(u64(data) + copied), run_length) }
		copied += run_length
	}
	return true
}
