// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

const stored_dependency_keys = ['id', 'minimum', 'before']
const stored_payload_keys = ['path', 'sha256', 'bytes', 'executable']
const stored_installed_keys = ['package', 'repository', 'public_key', 'sequence']
const stored_package_keys = ['id', 'version', 'architecture', 'name', 'description', 'homepage', 'license',
	'proprietary', 'firmware', 'kind', 'runtime', 'entrypoint', 'arguments', 'permissions',
	'associations', 'dependencies', 'files', 'sdk', 'window_protocol']

fn (mut r StoredReader) dependency(complete bool) !Dependency {
	r.expect(`{`)!
	mut value := Dependency{}
	mut accepted := false
	defer { if !accepted { unsafe { value.id.free(); value.minimum.free(); value.before.free() } } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_dependency_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = Dependency{ ...value, id: r.quoted(128)! } }
			1 { value = Dependency{ ...value, minimum: r.quoted(29)! } }
			2 { value = Dependency{ ...value, before: r.quoted(29)! } }
			else {}
		}
	}
	if (complete && seen != 7) || (!complete && seen & 1 == 0) { return error('missing required stored dependency field') }
	accepted = true
	return value
}

fn (mut r StoredReader) dependencies(maximum int, complete bool) ![]Dependency {
	r.expect(`[` )!
	mut values := []Dependency{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { for value in values { value.id.free(); value.minimum.free(); value.before.free() }; (&array(&values)).free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == maximum { return error('stored dependency count exceeds its bound') }
		value := r.dependency(complete)!
		pointer := unsafe { &value }
		unsafe { values.push_many(pointer, 1) }
	}
	accepted = true
	return values
}

fn (mut r StoredReader) payload() !Payload {
	r.expect(`{`)!
	mut value := Payload{}
	mut accepted := false
	defer { if !accepted { unsafe { value.path.free(); value.sha256.free() } } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_payload_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = Payload{ ...value, path: r.quoted(1024)! } }
			1 { value = Payload{ ...value, sha256: r.quoted(64)! } }
			2 { value = Payload{ ...value, bytes: r.unsigned(~u64(0))! } }
			3 { value = Payload{ ...value, executable: r.boolean()! } }
			else {}
		}
	}
	if seen != 15 { return error('missing required stored payload field') }
	accepted = true
	return value
}

fn (mut r StoredReader) payloads() ![]Payload {
	r.expect(`[` )!
	mut values := []Payload{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe { for value in values { value.path.free(); value.sha256.free() }; (&array(&values)).free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == max_files { return error('stored payload count exceeds its bound') }
		value := r.payload()!
		pointer := unsafe { &value }
		unsafe { values.push_many(pointer, 1) }
	}
	accepted = true
	return values
}

fn (mut r StoredReader) package() !Package {
	r.expect(`{`)!
	mut p := Package{}
	mut accepted := false
	defer { if !accepted { close_decoded_package(p) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_package_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { p = Package{ ...p, id: r.quoted(128)! } }
			1 { p = Package{ ...p, version: r.quoted(29)! } }
			2 { p = Package{ ...p, architecture: r.quoted(16)! } }
			3 { p = Package{ ...p, name: r.quoted(256)! } }
			4 { p = Package{ ...p, description: r.quoted(4096)! } }
			5 { p = Package{ ...p, homepage: r.quoted(1024)! } }
			6 { p = Package{ ...p, license: r.quoted(256)! } }
			7 { p = Package{ ...p, proprietary: r.boolean()! } }
			8 { p = Package{ ...p, firmware: r.boolean()! } }
			9 { p = Package{ ...p, kind: r.quoted(32)! } }
			10 { p = Package{ ...p, runtime: r.quoted(128)! } }
			11 { p = Package{ ...p, entrypoint: r.quoted(1024)! } }
			12 { p = Package{ ...p, arguments: r.strings(4096, 64)! } }
			13 { p = Package{ ...p, permissions: r.strings(256, 5)! } }
			14 { p = Package{ ...p, associations: r.strings(128, 128)! } }
			15 { p = Package{ ...p, dependencies: r.dependencies(128, true)! } }
			16 { p = Package{ ...p, files: r.payloads()! } }
			17 { p = Package{ ...p, sdk: int(r.unsigned(u64(max_i32))!) } }
			18 { p = Package{ ...p, window_protocol: int(r.unsigned(u64(max_i32))!) } }
			else {}
		}
	}
	// window_protocol is SDK 1's optional extension, defaulting to zero.
	if seen & 0x3ffff != 0x3ffff { return error('missing required stored package field') }
	accepted = true
	return p
}

fn close_stored_installed(value Installed) {
	unsafe { value.repository.free(); value.public_key.free() }
	close_decoded_package(value.package)
}

fn (mut r StoredReader) installed() !Installed {
	r.expect(`{`)!
	mut value := Installed{}
	mut accepted := false
	defer { if !accepted { close_stored_installed(value) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_installed_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = Installed{ ...value, package: r.package()! } }
			1 { value = Installed{ ...value, repository: r.quoted(128)! } }
			2 { value = Installed{ ...value, public_key: r.quoted(64)! } }
			3 { value = Installed{ ...value, sequence: r.unsigned(~u64(0))! } }
			else {}
		}
	}
	if seen != 15 { return error('missing required installed provenance field') }
	accepted = true
	return value
}

fn (mut r StoredReader) installed_packages() ![]Installed {
	r.expect(`[` )!
	mut values := []Installed{cap: 16}
	unsafe { values.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { for value in values { close_stored_installed(value) }; unsafe { (&array(&values)).free() } } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if values.len == 4096 { return error('stored package count exceeds its bound') }
		value := r.installed()!
		pointer := unsafe { &value }
		unsafe { values.push_many(pointer, 1) }
	}
	accepted = true
	return values
}
