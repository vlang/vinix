// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct DarwinRuneRange {
	last u32
	flags u32
}

fn darwin_rune_lookup(point u32, ranges &DarwinRuneRange, count int) u32 {
	mut low := 0
	mut high := count
	unsafe {
		for low < high {
			middle := low + (high - low) / 2
			if point > ranges[middle].last { low = middle + 1 } else { high = middle }
		}
		return ranges[low].flags
	}
}

fn darwin_maskrune(point i32, mask u64) i32 {
	if point < 0 || point > 0x10ffff || u32(mask) == 0 { return 0 }
	// Native libc owns the active global locale. Its class values differ from
	// Darwin's runetype flags, digit values and encoded screen widths.
	locale := C.setlocale(i32(C.LC_CTYPE), unsafe { nil })
	if locale == unsafe { nil } { panic('iOS: native character locale is unavailable') }
	mut flags := u32(0)
	if unsafe { C.strcmp(locale, c'C') == 0 || C.strcmp(locale, c'POSIX') == 0 } {
		flags = darwin_rune_lookup(u32(point), unsafe { &darwin_rune_c_ranges[0] }, darwin_rune_c_ranges.len)
	} else if C.strstr(locale, c'UTF-8') != unsafe { nil } || C.strstr(locale, c'UTF8') != unsafe { nil }
		|| C.strstr(locale, c'utf-8') != unsafe { nil } || C.strstr(locale, c'utf8') != unsafe { nil } {
		flags = darwin_rune_lookup(u32(point), unsafe { &darwin_rune_utf8_ranges[0] }, darwin_rune_utf8_ranges.len)
	} else {
		panic('iOS: non-UTF-8 rune locales are not implemented')
	}
	return i32(flags & u32(mask))
}

fn darwin_isspace(point i32) i32 {
	return if darwin_maskrune(point, 0x4000) != 0 { 1 } else { 0 }
}
