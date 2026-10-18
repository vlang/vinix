// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn index_document_field(parent string, key string) bool {
	if parent == '' { return key in ['format', 'repository', 'sequence', 'expires', 'packages']! }
	// Signed packages use the same fields as retained generation manifests.
	return state_document_field(if parent == 'packages' { 'package' } else { parent }, key)
}

fn index_required_fields(parent string, keys []string) ! {
	match parent {
		'' {
			for key in ['format', 'repository', 'sequence', 'expires', 'packages']! {
				if key !in keys { return error('missing required signed index field: ' + key) }
			}
		}
		'packages' {
			for key in ['id', 'version', 'architecture', 'name', 'description', 'homepage', 'license',
				'proprietary', 'firmware', 'kind', 'runtime', 'entrypoint', 'arguments', 'permissions',
				'associations', 'dependencies', 'files', 'sdk']! {
				if key !in keys { return error('missing required signed package field: ' + key) }
			}
		}
		'dependencies' {
			for key in ['id', 'minimum', 'before']! {
				if key !in keys { return error('missing required signed dependency field: ' + key) }
			}
		}
		'files' {
			for key in ['path', 'sha256', 'bytes', 'executable']! {
				if key !in keys { return error('missing required signed payload field: ' + key) }
			}
		}
		else {}
	}
}

fn index_value_type(parent string, key string, token u8) bool {
	if parent == '' {
		if key == 'packages' { return token == `[` }
		if key == 'repository' { return token == `"` }
		return token == `-` || (token >= `0` && token <= `9`)
	}
	if parent == 'packages' {
		if key in ['arguments', 'permissions', 'associations', 'dependencies', 'files']! { return token == `[` }
		if key in ['proprietary', 'firmware']! { return token in [u8(`t`), `f`]! }
		if key in ['sdk', 'window_protocol']! { return token == `-` || (token >= `0` && token <= `9`) }
		return token == `"`
	}
	if parent == 'files' {
		if key == 'executable' { return token in [u8(`t`), `f`]! }
		if key == 'bytes' { return token == `-` || (token >= `0` && token <= `9`) }
	}
	return token == `"`
}

// Signatures authenticate the original bytes before this decoder is called.
// Complete declarations prevent defaults, coercion or duplicate keys from
// silently changing publisher intent. window_protocol remains optional at zero.
fn decode_signed_index(repository string, text string, now i64) !Index {
	if text.len > max_metadata { return error(repository + ': repository index too large') }
	// Preserve signed-schema diagnostics before the bounded typed reader. Both
	// passes inspect the authenticated bytes without rewriting them.
	document_keys_schema(text, index_document_field, index_required_fields, index_value_type)!
	index := read_signed_index(text)!
	mut accepted := false
	defer { if !accepted { close_decoded_index(index) } }
	if index.format != 1 || index.repository != repository || index.sequence == 0
		|| index.expires <= now || index.packages.len > 4096 {
		return error(repository + ': expired, incompatible or misidentified repository metadata; refresh from its publisher')
	}
	mut seen := map[string]bool{}
	defer { unsafe { seen.free() } }
	for p in index.packages {
		p.validate()!
		identity := p.id + '/' + p.architecture + '/' + p.version
		defer { unsafe { identity.free() } }
		if identity in seen { return error(repository + ': duplicate package ' + identity) }
		seen[identity] = true
	}
	accepted = true
	return index
}

fn close_decoded_index(index Index) {
	unsafe { index.repository.free() }
	for package in index.packages { close_decoded_package(package) }
	unsafe { (&array(&index.packages)).free() }
}

fn manifest_document_field(parent string, key string) bool {
	return state_document_field(if parent == '' { 'package' } else { parent }, key)
}

fn manifest_value_type(parent string, key string, token u8) bool {
	return index_value_type(if parent == '' { 'packages' } else { parent }, key, token)
}

fn manifest_required_fields(parent string, keys []string) ! {
	index_required_fields(if parent == '' { 'packages' } else { parent }, keys)!
}

// Source templates retain their documented omitted-field defaults. Stored
// inventories must retain every declaration emitted by the pack commands.
fn decode_manifest(text string, inventory bool) !Package {
	if text.len > max_metadata { return error('publisher manifest exceeds metadata limit') }
	document_keys_schema(text, manifest_document_field,
		if inventory { manifest_required_fields } else { document_optional_fields }, manifest_value_type)!
	mut r := &StoredReader{ text: text }
	defer { unsafe { free(r) } }
	p := r.package_fields(inventory)!
	mut accepted := false
	defer { if !accepted { close_decoded_package(p) } }
	r.spaces()
	if r.position != text.len { return error('trailing publisher manifest data') }
	check_package_permissions(p)!
	accepted = true
	return p
}

// Independently decoded or copied records only. Resolver and transaction plans
// borrow their manifests; public preview observations own independent copies.
fn close_decoded_package(p Package) {
	unsafe {
		p.id.free(); p.version.free(); p.architecture.free(); p.name.free()
		p.description.free(); p.homepage.free(); p.license.free(); p.kind.free()
		p.runtime.free(); p.entrypoint.free()
		for value in p.arguments { value.free() }
		(&array(&p.arguments)).free()
		for value in p.permissions { value.free() }
		(&array(&p.permissions)).free()
		for value in p.associations { value.free() }
		(&array(&p.associations)).free()
		for dependency in p.dependencies { dependency.id.free(); dependency.minimum.free(); dependency.before.free() }
		(&array(&p.dependencies)).free()
		for file in p.files { file.path.free(); file.sha256.free() }
		(&array(&p.files)).free()
	}
}
