// SPDX-License-Identifier: GPL-2.0-or-later
module gem

// Backing accessors. Callers must not add an offset to phys_addr or virt_addr
// themselves: a GEM object's pages need not stay one physical run, and these
// are the only places that know how they are laid out.

// The physical address of byte `offset`, or none past the end or without
// backing.
pub fn (obj &GemObject) page_phys(offset u64) ?u64 {
	if obj == unsafe { nil } || obj.phys_addr == 0 || offset >= obj.size { return none }
	return obj.phys_addr + offset
}

// The physically contiguous run that starts at `offset` and is at most
// `length` bytes: its physical address and its length. Mapping a range walks
// these runs until it is covered.
pub fn (obj &GemObject) contiguous_run(offset u64, length u64) ?(u64, u64) {
	if obj == unsafe { nil } || obj.phys_addr == 0 || length == 0 || offset >= obj.size { return none }
	available := obj.size - offset
	return obj.phys_addr + offset, if length < available { length } else { available }
}

// The physical base of the whole object when it is one run, for devices that
// need a single contiguous buffer, such as display scanout.
pub fn (obj &GemObject) contiguous_phys() ?u64 {
	if obj == unsafe { nil } || obj.phys_addr == 0 { return none }
	phys, run := obj.contiguous_run(0, obj.size) or { return none }
	if run != obj.size { return none }
	return phys
}

// Copy `length` bytes into the backing at `offset` through the kernel's
// mapping of each run. False if the range is outside the object.
pub fn (obj &GemObject) write_bytes(offset u64, data voidptr, length u64) bool {
	if obj == unsafe { nil } || offset > obj.size || length > obj.size - offset { return false }
	if obj.virt_addr != 0 {
		// One kernel mapping covers the object: a contiguous run in the direct
		// map, or a host aperture.
		unsafe { C.memcpy(voidptr(obj.virt_addr + offset), data, length) }
		return true
	}
	if obj.external { return false }
	mut done := u64(0)
	for done < length {
		phys, run := obj.contiguous_run(offset + done, length - done) or { return false }
		unsafe { C.memcpy(voidptr(phys + higher_half), voidptr(u64(data) + done), run) }
		done += run
	}
	return true
}
