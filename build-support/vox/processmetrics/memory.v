// SPDX-License-Identifier: MIT
module processmetrics

import os

fn statm_space(byte u8) bool {
	return byte == ` ` || byte == `\t` || byte == `\n` || byte == `\r`
}

// statm reports pages, with resident pages in its second column. Parse the
// counters without allocating temporary strings on the once-per-second path.
pub fn memory_from_statm(text string, page_size u64) MemorySnapshot {
	if page_size == 0 { return MemorySnapshot{} }
	mut offset := 0
	mut resident := u64(0)
	for column in 0 .. 2 {
		for offset < text.len && statm_space(text[offset]) { offset++ }
		start := offset
		mut pages := u64(0)
		for offset < text.len && text[offset] >= `0` && text[offset] <= `9` {
			digit := u64(text[offset] - `0`)
			if pages > (~u64(0) - digit) / 10 { return MemorySnapshot{} }
			pages = pages * 10 + digit
			offset++
		}
		if offset == start || (offset < text.len && !statm_space(text[offset])) {
			return MemorySnapshot{}
		}
		if column == 1 { resident = pages }
	}
	if resident > ~u64(0) / page_size { return MemorySnapshot{} }
	return MemorySnapshot{ bytes: resident * page_size, available: true }
}

$if linux {
	pub fn memory_snapshot() MemorySnapshot {
		text := os.read_file('/proc/self/statm') or { return MemorySnapshot{} }
		defer { unsafe { text.free() } }
		return memory_from_statm(text, u64(os.page_size()))
	}
}
