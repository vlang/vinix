// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

const stored_configuration_keys = ['format', 'architecture', 'repositories', 'policy', 'launch_user']
const stored_repository_keys = ['id', 'url', 'public_key']
const stored_policy_keys = ['offline', 'allowed', 'pins', 'permissions', 'licenses', 'allow_firmware', 'reserve_bytes']

fn (mut r StoredReader) repository() !Repository {
	r.expect(`{`)!
	mut value := Repository{}
	mut accepted := false
	defer { if !accepted { unsafe { value.id.free(); value.url.free(); value.public_key.free() } } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_repository_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = Repository{ ...value, id: r.quoted(128)! } }
			1 { value = Repository{ ...value, url: r.quoted(4096)! } }
			2 { value = Repository{ ...value, public_key: r.quoted(64)! } }
			else {}
		}
	}
	if seen != 7 { return error('missing required stored repository field') }
	accepted = true
	return value
}

fn (mut r StoredReader) repositories() ![]Repository {
	r.expect(`[` )!
	mut values := []Repository{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { for value in values { value.id.free(); value.url.free(); value.public_key.free() }; (&array(&values)).free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 4096 { return error('stored repository count exceeds its bound') }
		value := r.repository()!
		pointer := unsafe { &value }
		unsafe { values.push_many(pointer, 1) }
	}
	accepted = true
	return values
}

fn (mut r StoredReader) policy() !Policy {
	return r.policy_fields(false)
}

fn (mut r StoredReader) policy_fields(complete bool) !Policy {
	r.expect(`{`)!
	mut value := if complete { Policy{ permissions: []string{} } } else { Policy{} }
	mut accepted := false
	defer { if !accepted { close_owned_policy(value) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_policy_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = Policy{ ...value, offline: r.boolean()! } }
			1 { value = Policy{ ...value, allowed: r.strings(256, 4096)! } }
			2 { value = Policy{ ...value, pins: r.dependencies(4096, false)! } }
			3 {
				permissions := r.strings(256, 5)!
				// Explicit permissions replace the legacy default's owned buffer.
				unsafe { for permission in value.permissions { permission.free() }; (&array(&value.permissions)).free() }
				value = Policy{ ...value, permissions: permissions }
			}
			4 { value = Policy{ ...value, licenses: r.strings(256, 4096)! } }
			5 { value = Policy{ ...value, allow_firmware: r.boolean()! } }
			6 { value = Policy{ ...value, reserve_bytes: r.unsigned(u64(1) << 40)! } }
			else {}
		}
	}
	if complete && seen != 127 { return error('missing required organization policy field') }
	accepted = true
	return value
}

fn read_stored_configuration(text string) !Config {
	if text.len > max_metadata { return error('package configuration exceeds metadata limit') }
	mut r := &StoredReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut value := Config{}
	mut accepted := false
	defer { if !accepted { close_decoded_configuration(value) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_configuration_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = Config{ ...value, format: int(r.unsigned(u64(max_i32))!) } }
			1 { value = Config{ ...value, architecture: r.quoted(16)! } }
			2 { value = Config{ ...value, repositories: r.repositories()! } }
			3 {
				policy := r.policy()!
				close_owned_policy(value.policy)
				value = Config{ ...value, policy: policy }
			}
			4 { value = Config{ ...value, launch_user: r.quoted(32)! } }
			else {}
		}
	}
	r.spaces()
	if r.position != text.len { return error('trailing package configuration data') }
	value.validate()!
	accepted = true
	return value
}
