// SPDX-License-Identifier: GPL-2.0-or-later
module buildcore

import os

pub fn shared_elf(header []u8) bool {
	return header.len >= 20 && header[..6] == [u8(0x7f), `E`, `L`, `F`, 2, 1] && header[16..20] == [u8(3), 0, 62, 0]
}

fn little(data []u8, begin int, length int) u64 {
	if begin >= data.len { return 0 }
	mut result := u64(0)
	end := if begin + length < data.len { begin + length } else { data.len }
	for i in begin .. end { result |= u64(data[i]) << u32((i - begin) * 8) }
	return result
}

pub fn static_translator(contents []u8, dynamic string) bool {
	if contents.len < 64 || contents[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1] || little(contents, 16, 2) !in [u64(2), 3] || little(contents, 18, 2) != 183 {
		return false
	}
	offset := little(contents, 32, 8)
	size := little(contents, 54, 2)
	count := little(contents, 56, 2)
	// Python arithmetic is unbounded. Test by subtraction so a large u64
// offset cannot wrap when the program-header table size is added.
	if size < 56 || count == 0 || offset > u64(contents.len) || count * size > u64(contents.len) - offset {
		return false
	}
	for i in u64(0) .. count {
		if little(contents, int(offset + i * size), 4) == 3 { return false }
	}
	return !dynamic.contains('(NEEDED)')
}

// Python's greedy .* selects the last [ that can be followed by nonempty
// non-] bytes and ]. Newlines delimit .*; the capture itself may span them.
pub fn needed(dynamic string) []string {
	mut result := []string{}
	mut begin := 0
	for begin < dynamic.len {
		found := dynamic[begin..].index('(NEEDED)') or { break }
		start := begin + found + 8
		line_end := dynamic[start..].index('\n') or { dynamic.len - start }
		mut selected := -1
		mut finish := -1
		for i in start .. start + line_end {
			if dynamic[i] != `[` { continue }
			end := dynamic[i + 1..].index(']') or { continue }
			if end == 0 { continue }
			selected = i + 1
			finish = selected + end
		}
		if selected >= 0 {
			result << dynamic[selected..finish]
			begin = finish + 1
		} else { begin = start }
	}
	return result
}

pub fn verify_dynamic(dynamic string, base string) ! {
	if !dynamic.contains('vk_icdNegotiateLoaderICDInterfaceVersion') {
		return PolicyError{'SystemExit', 'built Lavapipe lacks the Vulkan ICD entry point'}
	}
	for name in needed(dynamic) {
		mut present := false
		for directory in ['lib/x86_64-linux-gnu', 'usr/lib/x86_64-linux-gnu'] {
			path := if name.starts_with('/') { name } else { base + '/' + directory + '/' + name }
			if !path.contains('\x00') && os.exists(path) { present = true; break }
		}
		if !present { return PolicyError{'SystemExit', 'built Lavapipe needs a library the runtime lacks: ' + name} }
	}
}
