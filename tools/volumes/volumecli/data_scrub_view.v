// SPDX-License-Identifier: GPL-2.0-or-later
module volumecli

struct ScrubReportCursor {
	data &u8 = unsafe { nil }
	size int
mut:
	at int
}

// Borrowed bounded bytes only. Literal matching never relies on a terminator
// in the untrusted file, and numbers have one canonical decimal spelling.
fn scrub_report_literal(mut cursor ScrubReportCursor, literal &char) bool {
	unsafe {
		mut i := 0
		for literal[i] != 0 {
			if cursor.at >= cursor.size || cursor.data[cursor.at] != u8(literal[i]) { return false }
			cursor.at++; i++
		}
	}
	return true
}

fn scrub_report_number(mut cursor ScrubReportCursor) ?u64 {
	mut value := u64(0); start := cursor.at
	unsafe {
		for cursor.at < cursor.size && cursor.data[cursor.at] >= `0` && cursor.data[cursor.at] <= `9` {
			digit := u64(cursor.data[cursor.at] - `0`)
			if (cursor.at > start && cursor.data[start] == `0`) || value > (u64(-1) - digit) / 10 { return none }
			value = value * 10 + digit; cursor.at++
		}
	}
	if cursor.at == start { return none }; return value
}

fn scrub_report_hex(mut cursor ScrubReportCursor, output &u8) bool {
	if cursor.size - cursor.at < 64 { return false }
	unsafe {
		for i in 0 .. 32 {
			mut value := u8(0)
			for half in 0 .. 2 {
				byte := cursor.data[cursor.at]; cursor.at++
				if byte >= `0` && byte <= `9` { value = value * 16 + byte - `0` }
				else if byte >= `a` && byte <= `f` { value = value * 16 + byte - `a` + 10 }
				else { return false }
			}
			output[i] = value
		}
	}
	return true
}

// SR1 records no disk capacities or native sector sizes. Validate everything
// it does record: canonical syntax, bounded counts, saved row order, global
// slots, nonoverlapping 512-aligned signed-I/O extents and consistent findings.
// This is structural validation of historical evidence, not authentication.
@[direct_array_access]
fn scrub_report_valid(data &u8, size int) bool {
	if size <= 0 || size >= scrub_report_max { return false }
	mut cursor := unsafe { &ScrubReportCursor(C.alloca(sizeof(ScrubReportCursor))) }
	unsafe { *cursor = ScrubReportCursor{data: data, size: size} }
	if !scrub_report_literal(mut cursor, c'format=VINIXSR1 operation=scrubbed-data disks=') { return false }
	disks := scrub_report_number(mut cursor) or { return false }
	if disks == 0 || disks > 64 || !scrub_report_literal(mut cursor, c' mappings=') { return false }
	count := scrub_report_number(mut cursor) or { return false }
	if count > 64 || !scrub_report_literal(mut cursor, c' matched=') { return false }
	matched := scrub_report_number(mut cursor) or { return false }
	if matched > count || !scrub_report_literal(mut cursor, c' changed=') { return false }
	changed := scrub_report_number(mut cursor) or { return false }
	if changed != count - matched || !scrub_report_literal(mut cursor, c' algorithm=sha256 reference_sha256=') { return false }
	mut digest := [32]u8{}
	if !scrub_report_hex(mut cursor, &digest[0]) || !scrub_report_literal(mut cursor, c'\n') { return false }
	mut rows := [64]Request{}; mut indices := [64]u64{}; mut slots := u64(0); mut findings := u64(0)
	for i in 0 .. int(count) {
		if !scrub_report_literal(mut cursor, c'disk=') { return false }
		disk := scrub_report_number(mut cursor) or { return false }
		if disk >= disks || (i > 0 && disk < indices[i - 1]) || !scrub_report_literal(mut cursor, c' slot=') { return false }
		slot := scrub_report_number(mut cursor) or { return false }
		if slot >= 64 || slots & (u64(1) << slot) != 0 || !scrub_report_literal(mut cursor, c' offset=') { return false }
		offset := scrub_report_number(mut cursor) or { return false }
		if !scrub_report_literal(mut cursor, c' bytes=') { return false }
		length := scrub_report_number(mut cursor) or { return false }
		if offset > u64(0x7fffffffffffffff) || length == 0 || length > data_sha_max_bytes
			|| length > u64(0x7fffffffffffffff) - offset || offset % 512 != 0 || length % 512 != 0
			|| !scrub_report_literal(mut cursor, c' readonly=') { return false }
		readonly := scrub_report_number(mut cursor) or { return false }
		if readonly > 1 || !scrub_report_literal(mut cursor, c' result=') { return false }
		is_changed := unsafe { cursor.at < cursor.size && cursor.data[cursor.at] == `c` }
		if !scrub_report_literal(mut cursor, if is_changed { c'changed' } else { c'match' })
			|| !scrub_report_literal(mut cursor, c' expected_sha256=') { return false }
		mut expected := [32]u8{}; mut actual := [32]u8{}
		if !scrub_report_hex(mut cursor, &expected[0]) || !scrub_report_literal(mut cursor, c' actual_sha256=')
			|| !scrub_report_hex(mut cursor, &actual[0]) || !scrub_report_literal(mut cursor, c'\n') { return false }
		if (expected != actual) != is_changed { return false }
		for earlier in 0 .. i {
			other := rows[earlier]
			if indices[earlier] == disk && offset < other.offset + other.length && other.offset < offset + length { return false }
		}
		rows[i] = Request{slot: u32(slot), offset: offset, length: length, flags: readonly}; indices[i] = disk
		slots |= u64(1) << slot; if is_changed { findings++ }
	}
	return cursor.at == size && findings == changed
}

// Ordinary plain-data input policy. Keep the directory and input descriptor
// through output finalization; reserve the last byte for printf's terminator.
@[direct_array_access]
fn show_data_scrub_file(path &char) i32 {
	mut source := unsafe { &PlanEdit(C.alloca(sizeof(PlanEdit))) }; unsafe { *source = PlanEdit{} }
	defer { close_plan_edit(mut source) }
	if !open_plan_edit(path, mut source, false) { return 1 }
	mut info := C.stat{}
	if C.fstat(source.source, &info) != 0 || C.S_ISREG(info.st_mode) == 0 || info.st_size <= 0 || info.st_size >= scrub_report_max {
		return plan_error(c'data scrub report must be a bounded regular file')
	}
	mut text := [32768]u8{}; mut done := i64(0)
	for done < info.st_size {
		read := C.read(source.source, unsafe { &text[done] }, usize(info.st_size - done))
		if read < 0 && unsafe { C.errno == C.EINTR } { continue }
		if read <= 0 || read > info.st_size - done { return 1 }; done += read
	}
	mut extra := u8(0)
	for {
		read := C.read(source.source, &extra, 1); if read < 0 && unsafe { C.errno == C.EINTR } { continue }
		if read != 0 { return 1 }; break
	}
	if !scrub_report_valid(&text[0], int(done)) { return plan_error(c'invalid data scrub report syntax, rows or findings') }
	return finish_bundle_report(C.printf(c'%s', &text[0]) >= 0)
}
