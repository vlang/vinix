// SPDX-License-Identifier: GPL-2.0-or-later
module collectionstress

import os
import strconv

#include <unistd.h>
fn C.sleep(u32) u32

// Read the reservation counter, not slab RSS: retired namespace objects keep
// their conservative charge until the filesystem grace period has elapsed.
pub fn file_bytes(text string) !u64 {
	lines := text.split_into_lines()
	defer { unsafe { lines.free() } }
	mut found := false
	mut bytes := u64(0)
	for line in lines {
		fields := line.fields()
		defer { unsafe { fields.free() } }
		if fields.len == 0 || fields[0] != 'file' { continue }
		if found || fields.len != 3 { return error('ambiguous kernel file reservation counter') }
		for index in 1 .. 3 {
			field := fields[index]
			if field.len == 0 { return error('empty kernel file reservation counter') }
			for byte in field { if byte < `0` || byte > `9` { return error('invalid kernel file reservation counter') } }
			value := strconv.parse_uint(field, 10, 64) or {
				// NumError can borrow its input. Retire it before fields does.
				message := err.msg(); unsafe { message.free(); err.free() }
				return error('kernel file reservation counter exceeds u64')
			}
			if index == 2 { bytes = value }
		}
		found = true
	}
	if !found { return error('missing kernel file reservation counter') }
	return bytes
}

pub fn reservation_ceiling(baseline u64) !u64 {
	// A few proc/coordination objects may change while the observer runs. A
	// fixed ceiling prevents their allowance accumulating across child cases.
	allowance := u64(128 * 1024)
	if baseline > ~u64(0) - allowance { return error('kernel reservation ceiling overflow') }
	return baseline + allowance
}

pub fn current_file_bytes() !u64 {
	text := os.read_file('/proc/kernel-resources')!
	defer { unsafe { text.free() } }
	return file_bytes(text)
}

pub fn settle(label string, ceiling u64) ! {
	initial := current_file_bytes()!
	mut bytes := initial
	for waits in 0 .. 31 {
		if bytes <= ceiling {
			println('COLLECTION STRESS settled ' + label + ': initial=' + initial.str() + ' bytes=' + bytes.str() + ' waits=' + waits.str())
			return
		}
		if waits == 30 { break }
		C.sleep(1)
		bytes = current_file_bytes()!
	}
	return error('kernel file reservations did not settle after ' + label + ': bytes=' + bytes.str() + ' ceiling=' + ceiling.str())
}
