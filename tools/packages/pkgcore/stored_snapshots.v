// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

const stored_snapshot_keys = ['repository', 'text', 'signature']

fn (mut r StoredReader) cached_snapshot() !Snapshot {
	r.expect(`{`)!
	mut value := Snapshot{}
	mut accepted := false
	defer { if !accepted { close_decoded_snapshot(value) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_snapshot_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = Snapshot{ ...value, repository: r.repository()! } }
			1 { value = Snapshot{ ...value, text: r.quoted(max_metadata)! } }
			2 { value = Snapshot{ ...value, signature: r.quoted(256)! } }
			else {}
		}
	}
	if seen != 7 || !valid_repository(value.repository) || value.text == '' || value.signature == '' {
		return error('invalid or incomplete cached repository snapshot')
	}
	accepted = true
	return value
}

// Decode the wrapper only. Signed bytes stay opaque until authentication and
// index admission; legacy signature whitespace is preserved exactly too.
fn read_stored_snapshots(text string) ![]Snapshot {
	if text.len > max_metadata { return error('cached repository metadata exceeds its size limit') }
	mut r := &StoredReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`[` )!
	mut values := []Snapshot{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { close_decoded_snapshots(values) } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 4096 { return error('cached repository metadata exceeds its identity limit') }
		value := r.cached_snapshot()!
		// Transfer before checking uniqueness so a refusal retires this record.
		pointer := unsafe { &value }
		unsafe { values.push_many(pointer, 1) }
		for index in 0 .. values.len - 1 {
			if values[index].repository.id == value.repository.id { return error('duplicate cached repository identity') }
		}
	}
	r.spaces()
	if r.position != text.len { return error('trailing cached repository metadata') }
	accepted = true
	return values
}
