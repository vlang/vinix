// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

const stored_history_keys = ['format', 'repositories']
const stored_release_history_keys = ['format', 'indexes']
const stored_floor_keys = ['id', 'public_key', 'sequence', 'index_sha256']

fn (mut r StoredReader) history_floor() !RepositoryFloor {
	r.expect(`{`)!
	mut value := RepositoryFloor{}
	mut accepted := false
	defer { if !accepted { unsafe { value.id.free(); value.public_key.free(); value.index_sha256.free() } } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_floor_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = RepositoryFloor{ ...value, id: r.quoted(128)! } }
			1 { value = RepositoryFloor{ ...value, public_key: r.quoted(64)! } }
			2 { value = RepositoryFloor{ ...value, sequence: r.unsigned(~u64(0))! } }
			3 { value = RepositoryFloor{ ...value, index_sha256: r.quoted(64)! } }
			else {}
		}
	}
	if seen != 15 || !identifier(value.id) || !digest_valid(value.public_key)
		|| !digest_valid(value.index_sha256) || value.sequence == 0 { return error('invalid or incomplete repository history floor') }
	accepted = true
	return value
}

fn (mut r StoredReader) history_floors() ![]RepositoryFloor {
	r.expect(`[` )!
	mut values := []RepositoryFloor{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { close_decoded_history(TrustHistory{ repositories: values }) } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 4096 { return error('repository history exceeds its identity limit') }
		value := r.history_floor()!
		// Transfer before checking uniqueness so refusal retires this record too.
		// Comparing borrowed fields avoids allocating concatenated identity keys.
		pointer := unsafe { &value }
		unsafe { values.push_many(pointer, 1) }
		for index in 0 .. values.len - 1 {
			if values[index].id == value.id && values[index].public_key == value.public_key {
				return error('duplicate repository history identity')
			}
		}
	}
	accepted = true
	return values
}

fn read_stored_history(text string, publisher bool) !TrustHistory {
	if text.len > max_metadata { return error('repository history exceeds metadata limit') }
	mut r := &StoredReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut value := TrustHistory{}
	mut accepted := false
	defer { if !accepted { close_decoded_history(value) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(if publisher { stored_release_history_keys } else { stored_history_keys }, seen)!; seen |= u32(1) << field
		match field {
			0 { value = TrustHistory{ ...value, format: int(r.unsigned(u64(max_i32))!) } }
			1 { value = TrustHistory{ ...value, repositories: r.history_floors()! } }
			else {}
		}
	}
	r.spaces()
	if seen != 3 || value.format != 1 || r.position != text.len { return error('unsupported, incomplete or trailing repository history') }
	accepted = true
	return value
}
