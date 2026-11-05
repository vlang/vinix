// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit host controls. Fixture construction may allocate; guest reads do not.
module perfheap

import os

fn C.pipe(&i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.fcntl(i32, i32, ...voidptr) i32

fn fixture(objects string, pages string, large string, written string) string {
	mut text := schema_header
	for size in class_sizes {
		number := size.str()
		text += 'size-' + number + ' ' + number + ' ' + objects + ' ' + pages + '\n'
	}
	return text + 'large - - ' + large + '\n# written after free ' + written + '\n'
}

fn raw_matches(snapshot &Snapshot, text string) bool {
	if !snapshot.valid || snapshot.raw_len != text.len { return false }
	for index, byte in text { if snapshot.raw[index] != byte { return false } }
	return true
}

fn refuse_parse(text string, out &Snapshot) ! {
	mut refused := false
	parse_snapshot(text.str, text.len, out) or { refused = true }
	require(refused && !out.valid && out.raw_len == 0, 'bad parser input was accepted or left valid output')!
}

fn refuse_read(path string, out &Snapshot) ! {
	mut refused := false
	read_snapshot(path, out) or { refused = true }
	require(refused && !out.valid && out.raw_len == 0, 'bad reader input was accepted or left valid output')!
}

fn refuse_compare(before &Snapshot, after &Snapshot, out &Delta) ! {
	mut refused := false
	compare(before, after, out) or { refused = true }
	require(refused && !out.valid, 'bad comparison was accepted or left valid output')!
}

fn refuse_flatness(before &Snapshot, after &Snapshot) ! {
	mut refused := false
	qualify_flatness(before, after) or { refused = true }
	require(refused, 'nonflat or written-after-free snapshots qualified as clean')!
}

// The payload is less than POSIX PIPE_BUF and the writer is closed before any
// read. These controls cannot wait for a writer or for a pipe larger than its
// guaranteed capacity. The internal reader borrows, and never closes, its fd.
fn pipe_control(text string, accepted bool, out &Snapshot) ! {
	require(text.len > 0 && text.len < 4096, 'pipe fixture exceeds safe prewrite bound')!
	mut descriptors := [2]i32{}
	require(C.pipe(unsafe { &descriptors[0] }) == 0, 'cannot create reader control pipe')!
	mut writer_closed := false
	defer {
		C.close(descriptors[0])
		if !writer_closed { C.close(descriptors[1]) }
	}
	amount := C.write(descriptors[1], text.str, usize(text.len))
	require(amount == text.len, 'short pipe fixture write')!
	writer_closed = true
	require(C.close(descriptors[1]) == 0, 'pipe writer close failed')!
	mut refused := false
	read_from_fd(descriptors[0], out) or { refused = true }
	if accepted {
		require(!refused && raw_matches(out, text), 'complete pipe snapshot was not preserved')!
	} else {
		require(refused && !out.valid && out.raw_len == 0, 'truncated pipe snapshot was accepted')!
	}
	require(C.fcntl(descriptors[0], C.F_GETFD) >= 0, 'borrowed reader closed its descriptor')!
}

// Returns the number of completed controls, rather than a hard-coded PASS count.
// No assertion or required side effect disappears under -prod.
pub fn selfcheck(fresh_root string) !int {
	require(fresh_root.starts_with('/') && !os.exists(fresh_root) && !os.is_link(fresh_root),
		'heap controls need a fresh absolute external directory')!
	os.mkdir(fresh_root, mode: 0o700)!
	base := fixture('20', '4', '9', '3')
	mut before := Snapshot{}
	mut after := Snapshot{}
	mut delta := Delta{}
	mut checks := 0
	parse_snapshot(base.str, base.len, unsafe { &before })!
	require(raw_matches(unsafe { &before }, base) && before.classes[13].objects == 20
		&& before.classes[13].pages == 4 && before.large_pages == 9
		&& before.written_after_free == 3, 'complete snapshot or raw retention differs')!
	checks++
	// Each proper prefix must refuse, including one ending at a complete row.
	for length in 0 .. base.len {
		mut refused := false
		parse_snapshot(base.str, length, unsafe { &after }) or { refused = true }
		require(refused && !after.valid && after.raw_len == 0, 'truncated prefix was accepted')!
		checks++
	}
	for bad in [base.replace(schema_header, '# class size objects pages\n'),
		base.replace('size-16 16 20 4\n', ''),
		base.replace('size-32 32 20 4\n', 'size-16 16 20 4\n'),
		base.replace('size-16 16 20 4\nsize-32 32 20 4\n', 'size-32 32 20 4\nsize-16 16 20 4\n'),
		base.replace('size-16 16 ', 'size-16 32 '),
		base.replace('size-16 16 ', 'size-016 16 '),
		base.replace('size-16 16 20 4', 'size-16 16 -1 4'),
		base.replace('size-16 16 20 4', 'size-16 16 +1 4'),
		base.replace('size-16 16 20 4', 'size-16 16 01 4'),
		base.replace('size-16 16 20 4', 'size-16 16 1x 4'),
		base.replace('size-16 16 20 4', 'size-16 16 18446744073709551616 4'),
		base.replace('size-16 16 20 4', 'size-16 16 20\t4'),
		base.replace('large - - 9\n', ''),
		base.replace('large - - 9\n', 'large - - 9\nlarge - - 9\n'),
		base.replace('large - - 9\n', 'large - - -1\n'),
		base.replace('# written after free 3\n', ''),
		base.replace('# written after free 3\n', '# unexpected 3\n'),
		base + '\n', base + '\x00', base + 'x'.repeat(raw_capacity)] {
		refuse_parse(bad, unsafe { &after })!
		checks++
	}
	mut nil_refused := false
	parse_snapshot(unsafe { nil }, base.len, unsafe { &after }) or { nil_refused = true }
	require(nil_refused && !after.valid, 'nil parser input was accepted')!
	checks++
	maximum := fixture('18446744073709551615', '18446744073709551615',
		'18446744073709551615', '18446744073709551615')
	parse_snapshot(maximum.str, maximum.len, unsafe { &after })!
	require(after.classes[0].objects == unsigned_max && after.large_pages == unsigned_max,
		'full u64 counters were truncated')!
	compare(unsafe { &after }, unsafe { &after }, unsafe { &delta })!
	require(delta.valid && delta.bytes == 0 && delta.large_pages == 0, 'equal maximum counters differ')!
	checks++
	changed := fixture('21', '5', '10', '4')
	parse_snapshot(changed.str, changed.len, unsafe { &after })!
	compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
	require(delta.valid && delta.bytes == 11200 && delta.large_pages == 1
		&& delta.written_after_free == 1, 'positive exact byte or special-counter deltas differ')!
	for row in delta.classes { require(row.objects == 1 && row.pages == 1, 'class delta omitted')! }
	checks++
	compare(unsafe { &after }, unsafe { &before }, unsafe { &delta })!
	require(delta.valid && delta.bytes == -11200 && delta.large_pages == -1
		&& delta.written_after_free == -1, 'negative exact deltas differ')!
	checks++
	parse_snapshot(base.str, base.len, unsafe { &after })!
	after.classes[0] = ClassSnapshot{size: 16, objects: 21, pages: 4}
	compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
	require(delta.bytes == 16 && delta.classes[0].objects == 1 && delta.bytes / 200 == 0,
		'small exact delta was lost through rate truncation')!
	checks++
	after.classes[0] = ClassSnapshot{size: 17, objects: 20, pages: 4}
	refuse_compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
	checks++
	for field in 0 .. 5 {
		parse_snapshot(base.str, base.len, unsafe { &after })!
		match field {
			0 { after.classes[0] = ClassSnapshot{size: 16, objects: unsigned_max, pages: 4} }
			1 { after.classes[0] = ClassSnapshot{size: 16, objects: 20, pages: unsigned_max} }
			2 { after.large_pages = unsigned_max }
			3 { after.written_after_free = unsigned_max }
			else { after.valid = false }
		}
		refuse_compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
		checks++
	}
	// Exercise arithmetic boundaries independently from ordinary small counters.
	require(difference(u64(signed_max) + 1, 0)! == signed_min
		&& difference(0, u64(signed_max))! == signed_max
		&& scaled(signed_min / 16, 16)! == signed_min, 'signed boundary arithmetic differs')!
	checks++
	for kind in 0 .. 3 {
		mut refused := false
		match kind {
			0 { scaled(signed_max, 16) or { refused = true } }
			1 { sum(signed_max, 1) or { refused = true } }
			else { sum(signed_min, -1) or { refused = true } }
		}
		require(refused, 'overflow arithmetic was accepted')!
		checks++
	}
	clean := fixture('20', '4', '9', '0')
	parse_snapshot(clean.str, clean.len, unsafe { &before })!
	parse_snapshot(clean.str, clean.len, unsafe { &after })!
	qualify_flatness(unsafe { &before }, unsafe { &after })!
	checks++
	// Equal positive footer counts remain observable data, but never clean.
	parse_snapshot(base.str, base.len, unsafe { &before })!
	parse_snapshot(base.str, base.len, unsafe { &after })!
	refuse_flatness(unsafe { &before }, unsafe { &after })!
	checks++
	parse_snapshot(clean.str, clean.len, unsafe { &before })!
	new_corruption := fixture('20', '4', '9', '1')
	parse_snapshot(new_corruption.str, new_corruption.len, unsafe { &after })!
	refuse_flatness(unsafe { &before }, unsafe { &after })!
	checks++
	parse_snapshot(new_corruption.str, new_corruption.len, unsafe { &before })!
	parse_snapshot(clean.str, clean.len, unsafe { &after })!
	refuse_flatness(unsafe { &before }, unsafe { &after })!
	checks++
	for kind in 0 .. 4 {
		parse_snapshot(clean.str, clean.len, unsafe { &before })!
		parse_snapshot(clean.str, clean.len, unsafe { &after })!
		match kind {
			0 {
				after.classes[0] = ClassSnapshot{size: 16, objects: 21, pages: 4}
				compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
				require(delta.bytes == 16 && delta.bytes / 200 == 0,
					'qualification truncation fixture does not hide the derived rate')!
			}
			1 { after.classes[0] = ClassSnapshot{size: 16, objects: 20, pages: 5} }
			2 {
				after.classes[0] = ClassSnapshot{size: 16, objects: 22, pages: 4}
				after.classes[1] = ClassSnapshot{size: 32, objects: 19, pages: 4}
				compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
				require(delta.bytes == 0, 'class cancellation fixture does not cancel')!
			}
			else { after.large_pages++ }
		}
		refuse_flatness(unsafe { &before }, unsafe { &after })!
		checks++
	}
	os.write_file(fresh_root + '/complete', base)!
	read_snapshot(fresh_root + '/complete', unsafe { &after })!
	require(raw_matches(unsafe { &after }, base), 'regular-file snapshot was not preserved')!
	checks++
	refuse_read(fresh_root + '/absent', unsafe { &after })!
	checks++
	refuse_read(fresh_root, unsafe { &after })!
	checks++
	os.write_file(fresh_root + '/truncated', base[..base.len - 1])!
	refuse_read(fresh_root + '/truncated', unsafe { &after })!
	checks++
	for length in [raw_capacity, raw_capacity + 1] {
		path := fresh_root + '/bounded-' + length.str()
		os.write_file(path, base + 'x'.repeat(length - base.len))!
		refuse_read(path, unsafe { &after })!
		checks++
	}
	pipe_control(base, true, unsafe { &after })!
	checks++
	pipe_control(base[..base.len - 1], false, unsafe { &after })!
	checks++
	mut bad_fd_refused := false
	read_from_fd(-1, unsafe { &after }) or { bad_fd_refused = true }
	require(bad_fd_refused && !after.valid && after.raw_len == 0, 'failed descriptor read was accepted')!
	checks++
	return checks
}
