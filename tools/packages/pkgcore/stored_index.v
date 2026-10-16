// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

const signed_index_keys = ['format', 'repository', 'sequence', 'expires', 'packages']

fn (mut r StoredReader) index_expiry() !i64 {
	r.spaces()
	negative := r.position < r.text.len && r.text[r.position] == `-`
	if negative {
		r.position++
		if r.position >= r.text.len || r.text[r.position] < `0` || r.text[r.position] > `9` {
			return error('signed index expiry requires an integer')
		}
	}
	value := r.unsigned(u64(max_i64) + if negative { u64(1) } else { u64(0) })!
	if negative && value != 0 { return -i64(value - 1) - 1 }
	return i64(value)
}

fn (mut r StoredReader) index_packages() ![]Package {
	r.expect(`[` )!
	mut values := []Package{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer {
		if !accepted {
			for value in values { close_decoded_package(value) }
			unsafe { (&array(&values)).free() }
		}
	}
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 4096 { return error('signed package count exceeds its bound') }
		value := r.package()!
		pointer := unsafe { &value }
		unsafe { values.push_many(pointer, 1) }
	}
	accepted = true
	return values
}

// Internal typed decoding only; callers first authenticate and check the signed
// field schema, then validate the envelope and every package declaration.
fn read_signed_index(text string) !Index {
	mut r := &StoredReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut value := Index{}
	mut accepted := false
	defer { if !accepted { close_decoded_index(value) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(signed_index_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = Index{ ...value, format: int(r.unsigned(u64(max_i32))!) } }
			1 { value = Index{ ...value, repository: r.quoted(128)! } }
			2 { value = Index{ ...value, sequence: r.unsigned(~u64(0))! } }
			3 { value = Index{ ...value, expires: r.index_expiry()! } }
			4 { value = Index{ ...value, packages: r.index_packages()! } }
			else {}
		}
	}
	r.spaces()
	if seen != 31 || r.position != text.len { return error('incomplete or trailing signed repository index') }
	accepted = true
	return value
}
