// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

const stored_state_keys = ['format', 'generation', 'previous', 'architecture', 'requested', 'packages']

fn read_stored_state(text string, architecture string) !State {
	if text.len > max_metadata { return error('persistent package state exceeds metadata limit') }
	mut r := &StoredReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut value := State{}
	mut accepted := false
	defer { if !accepted { close_decoded_state(value) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_state_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = State{ ...value, format: int(r.unsigned(u64(max_i32))!) } }
			1 { value = State{ ...value, generation: r.unsigned(~u64(0))! } }
			2 { value = State{ ...value, previous: r.unsigned(~u64(0))! } }
			3 { value = State{ ...value, architecture: r.quoted(16)! } }
			4 { value = State{ ...value, requested: r.strings(128, 4096)! } }
			5 { value = State{ ...value, packages: r.installed_packages()! } }
			else {}
		}
	}
	r.spaces()
	if seen != 63 || r.position != text.len { return error('incomplete or trailing persistent package state') }
	validate_state(value, architecture)!
	accepted = true
	return value
}
