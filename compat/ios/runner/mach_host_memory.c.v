// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct MachHostMemory {
mut:
	total u64
	free u64
	cached u64
	slab u64
	compressed u64
	uncompressed u64
	pageouts u64
	pageins u64
}

fn mach_host_amount(data &u8, start int, end int, kib bool) ?u64 {
	mut at := start
	unsafe {
		for at < end && (data[at] == ` ` || data[at] == `\t`) { at++ }
		begin := at; mut value := u64(0)
		for at < end && data[at] >= `0` && data[at] <= `9` {
			digit := u64(data[at] - `0`)
			if value > (~u64(0) - digit) / 10 { return none }
			value = value * 10 + digit; at++
		}
		if at == begin { return none }
		for at < end && (data[at] == ` ` || data[at] == `\t`) { at++ }
		if kib {
			if end - at < 2 || data[at] != `k` || data[at + 1] != `B` || value > ~u64(0) / 1024 { return none }
			value *= 1024; at += 2
		}
		for at < end && (data[at] == ` ` || data[at] == `\t`) { at++ }
		if at != end { return none }
		return value
	}
}

// No V strings/slices or dynamic containers on the repeated snapshot path.
// Unknown fields are ignored; malformed/duplicate mapped fields reject the
// whole snapshot. Missing optional Vinix counters stay zero.
fn mach_host_memory_parse(data &u8, length int, output &MachHostMemory) bool {
	mut values := [8]u64{}; mut present := u32(0); mut start := 0
	for end in 0 .. length + 1 {
		if end < length && unsafe { data[end] } != `\n` { continue }
		mut colon := start
		for colon < end && unsafe { data[colon] } != `:` { colon++ }
		mut field := -1
		for i, name in ['MemTotal', 'MemFree', 'Cached', 'Slab', 'Zswap', 'Zswapped', 'VinixPageouts', 'VinixRefaults']! {
			if proc_memory_matches(data, start, colon, name) { field = i; break }
		}
		if field >= 0 {
			if colon == end || present & (u32(1) << field) != 0 { return false }
			value := mach_host_amount(data, colon + 1, end, field < 6) or { return false }
			values[field] = value; present |= u32(1) << field
		}
		start = end + 1
	}
	if present & 3 != 3 || values[0] == 0 || values[1] > values[0] { return false }
	unsafe { *output = MachHostMemory{total: values[0], free: values[1], cached: values[2], slab: values[3], compressed: values[4], uncompressed: values[5], pageouts: values[6], pageins: values[7]} }
	return true
}

fn mach_host_memory_read(output &MachHostMemory) bool {
	mut bytes := [8192]u8{}
	length := proc_memory_read(c'/proc/meminfo', unsafe { &bytes[0] }, bytes.len)
	if length < 0 { return false }
	return mach_host_memory_parse(unsafe { &bytes[0] }, length, output)
}

fn mach_host_statistics_count(requested u32, wide bool) u32 {
	if wide {
		return if requested >= 62 { u32(62) } else if requested >= 40 { u32(40) } else if requested >= 38 { u32(38) } else if requested >= 24 { u32(24) } else { u32(0) }
	}
	return if requested >= 15 { u32(15) } else if requested >= 14 { u32(14) } else if requested >= 12 { u32(12) } else { u32(0) }
}

fn mach_host_saturate(value u64) u32 { return u32(if value > 0xffffffff { u64(0xffffffff) } else { value }) }
fn mach_host_min(left u64, right u64) u64 { return if left < right { left } else { right } }

// Vinix exposes free pages, resident file cache, kernel heap and compressed
// storage, without Darwin active/inactive queues. Report cache as inactive,
// slab as wired and the remaining resident pages as active. Bound each class
// by the remaining total since the kernel counters are sampled separately.
// Unsupported lifetime/tagging counters have no Vinix equivalent and stay zero.
fn mach_host_statistics_copy(memory MachHostMemory, wide bool, length u32, output voidptr, count &u32) {
	page := u64(C.getpagesize())
	total := memory.total / page; free_pages := memory.free / page
	mut remaining := total - free_pages
	inactive := mach_host_min(memory.cached / page, remaining); remaining -= inactive
	compressor := mach_host_min(memory.compressed / page + u64(memory.compressed % page != 0), remaining); remaining -= compressor
	wired := mach_host_min(memory.slab / page, remaining); remaining -= wired
	mut words := [62]u32{}
	words[0] = mach_host_saturate(free_pages); words[1] = mach_host_saturate(remaining)
	words[2] = mach_host_saturate(inactive); words[3] = mach_host_saturate(wired)
	if wide {
		words[8] = u32(memory.pageins); words[9] = u32(memory.pageins >> 32)
		words[10] = u32(memory.pageouts); words[11] = u32(memory.pageouts >> 32)
		words[32] = mach_host_saturate(compressor); words[34] = mach_host_saturate(inactive); words[35] = mach_host_saturate(remaining)
		words[36] = u32(memory.uncompressed / page); words[37] = u32((memory.uncompressed / page) >> 32)
	} else { words[6] = mach_host_saturate(memory.pageins); words[7] = mach_host_saturate(memory.pageouts) }
	unsafe { C.memcpy(output, voidptr(&words[0]), usize(length) * 4); C.memcpy(voidptr(count), voidptr(&length), 4) }
}
