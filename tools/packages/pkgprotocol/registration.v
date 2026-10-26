// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

// Presentation projection of an installed generation. Trust, dependencies,
// payload verification and execution remain the package service's authority.
pub struct RegisteredPackage {
pub:
	id string
	name string
	description string
	architecture string
	kind string
	permissions []string
	associations []string
}

pub struct RegistrationSnapshot {
pub:
	format int
	generation u64
	architecture string
	packages []RegisteredPackage
}

const registration_keys = ['format', 'generation', 'architecture', 'packages']
const registration_installation_keys = ['package']
const registration_package_keys = ['id', 'name', 'description', 'architecture', 'kind', 'permissions', 'associations']

fn close_registered_package(p RegisteredPackage) {
	unsafe {
		p.id.free(); p.name.free(); p.description.free(); p.architecture.free(); p.kind.free()
		for value in p.permissions { value.free() }; (&array(&p.permissions)).free()
		for value in p.associations { value.free() }; (&array(&p.associations)).free()
	}
}

pub fn (mut snapshot RegistrationSnapshot) close() {
	unsafe {
		snapshot.architecture.free()
		for p in snapshot.packages { close_registered_package(p) }
		(&array(&snapshot.packages)).free()
	}
	snapshot = RegistrationSnapshot{}
}

fn (snapshot &RegistrationSnapshot) validate() ! {
	if snapshot.format != 1 || snapshot.generation == 0 || snapshot.architecture !in ['aarch64', 'x86_64']! {
		return error('invalid package registration header')
	}
	mut ids := map[string]bool{}
	defer { unsafe { ids.free() } }
	for p in snapshot.packages {
		if !identifier(p.id) || p.id in ids || p.name == '' || !printable(p.name, 256)
			|| !printable(p.description, 4096) || p.architecture !in [snapshot.architecture, 'all']
			|| p.kind !in ['native', 'linux', 'windows', 'apple', 'runtime', 'data']!
			|| (p.architecture == 'all' && p.kind != 'data') || !view_permissions(p.permissions) {
			return error('invalid package registration')
		}
		ids[p.id] = true
		for mime in p.associations {
			if !valid_mime_association(mime) {
				return error('invalid package MIME registration')
			}
		}
	}
}

fn (mut r MetadataReader) parse_registered_package() !RegisteredPackage {
	r.expect(`{`)!
	mut p := RegisteredPackage{}
	mut accepted := false
	defer { if !accepted { close_registered_package(p) } }
	mut seen := u32(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.view_member(registration_package_keys, seen)!
		if member >= 0 { seen |= u32(1) << member }
		match member {
			0 { p = RegisteredPackage{ ...p, id: r.quoted(128)! } }
			1 { p = RegisteredPackage{ ...p, name: r.quoted(256)! } }
			2 { p = RegisteredPackage{ ...p, description: r.quoted(4096)! } }
			3 { p = RegisteredPackage{ ...p, architecture: r.quoted(16)! } }
			4 { p = RegisteredPackage{ ...p, kind: r.quoted(16)! } }
			5 { p = RegisteredPackage{ ...p, permissions: r.strings(16, 5)! } }
			6 { p = RegisteredPackage{ ...p, associations: r.strings(128, 128)! } }
			else { r.skip_view_extension(0)! }
		}
	}
	if seen != 127 { return error('missing package registration field') }
	accepted = true
	return p
}

fn (mut r MetadataReader) parse_registered_installation() !RegisteredPackage {
	r.expect(`{`)!
	mut p := RegisteredPackage{}
	mut accepted := false
	defer { if !accepted { close_registered_package(p) } }
	mut seen := u32(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.view_member(registration_installation_keys, seen)!
		if member == 0 { seen = 1; p = r.parse_registered_package()! }
		else { r.skip_view_extension(0)! }
	}
	if seen != 1 { return error('missing installed package registration') }
	accepted = true
	return p
}

fn (mut r MetadataReader) parse_registered_packages() ![]RegisteredPackage {
	r.expect(`[`)!
	mut packages := []RegisteredPackage{cap: 16}
	unsafe { packages.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe {
		for p in packages { close_registered_package(p) }; (&array(&packages)).free()
	} } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if packages.len == 4096 { return error('package registration exceeds its package limit') }
		p := r.parse_registered_installation()!
		pointer := unsafe { &p }
		unsafe { packages.push_many(pointer, 1) }
	}
	accepted = true
	return packages
}

fn (mut r MetadataReader) parse_registration() !RegistrationSnapshot {
	r.expect(`{`)!
	mut snapshot := RegistrationSnapshot{}
	mut accepted := false
	defer { if !accepted { snapshot.close() } }
	mut seen := u32(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		member := r.view_member(registration_keys, seen)!
		if member >= 0 { seen |= u32(1) << member }
		match member {
			0 { snapshot = RegistrationSnapshot{ ...snapshot, format: int(r.unsigned(1)!) } }
			1 { snapshot = RegistrationSnapshot{ ...snapshot, generation: r.unsigned(~u64(0))! } }
			2 { snapshot = RegistrationSnapshot{ ...snapshot, architecture: r.quoted(16)! } }
			3 { snapshot = RegistrationSnapshot{ ...snapshot, packages: r.parse_registered_packages()! } }
			else { r.skip_view_extension(0)! }
		}
	}
	if seen != 15 { return error('missing package registration envelope field') }
	snapshot.validate()!
	accepted = true
	return snapshot
}

// Known presentation fields are required, unique and typed. Other service-owned
// state fields are syntax-checked without retaining payload/provenance trees.
// Decoded values, including partial records on refusal, have explicit ownership.
pub fn decode_registration(text string) !RegistrationSnapshot {
	if text.len > 8 * 1024 * 1024 { return error('package registration exceeds metadata limit') }
	mut reader := &MetadataReader{ text: text }
	defer { unsafe { free(reader) } }
	mut snapshot := reader.parse_registration()!
	reader.spaces()
	if reader.position != text.len { snapshot.close(); return error('trailing package registration metadata') }
	return snapshot
}
