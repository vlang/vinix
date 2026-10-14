// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os

// Generations are written by the service, rather than supplied as manifest
// templates. Every state envelope field must survive storage and decoding.
struct PersistentStateInput {
	format int @[required]
	generation u64 @[required]
	previous u64 @[required]
	architecture string @[required]
	requested []string @[required]
	packages []Installed @[required]
}

fn state_document_field(parent string, key string) bool {
	return match parent {
		'' { key in ['format', 'generation', 'previous', 'architecture', 'requested', 'packages']! }
		'packages' { key in ['package', 'repository', 'public_key', 'sequence']! }
		'package' { key in ['id', 'version', 'architecture', 'name', 'description', 'homepage', 'license',
			'proprietary', 'firmware', 'kind', 'runtime', 'entrypoint', 'arguments', 'permissions',
			'associations', 'dependencies', 'files', 'sdk', 'window_protocol']! }
		'dependencies' { key in ['id', 'minimum', 'before']! }
		'files' { key in ['path', 'sha256', 'bytes', 'executable']! }
		else { false }
	}
}

fn state_required_fields(parent string, keys []string) ! {
	if parent == '' {
		for key in ['format', 'generation', 'previous', 'architecture', 'requested', 'packages']! {
			if key !in keys { return error('missing required persistent state field: ' + key) }
		}
	} else if parent == 'packages' {
		for key in ['package', 'repository', 'public_key', 'sequence']! {
			if key !in keys { return error('missing required installed provenance field: ' + key) }
		}
	} else {
		// Retained manifests must preserve the complete signed declarations,
		// including explicit false/empty values. SDK 1's optional window_protocol
		// remains compatible with generations written before that extension.
		index_required_fields(if parent == 'package' { 'packages' } else { parent }, keys)!
	}
}

fn state_value_type(parent string, key string, token u8) bool {
	if parent == '' {
		if key in ['requested', 'packages']! { return token == `[` }
		if key == 'architecture' { return token == `"` }
		return token >= `0` && token <= `9`
	}
	if parent == 'packages' {
		if key == 'package' { return token == `{` }
		if key == 'sequence' { return token >= `0` && token <= `9` }
		return token == `"`
	}
	return index_value_type(if parent == 'package' { 'packages' } else { parent }, key, token)
}

fn decode_persistent_state(text string, architecture string) !State {
	if text.len > max_metadata { return error('persistent package state exceeds metadata limit') }
	input := json2.decode[PersistentStateInput](text, strict: true)!
	state := State{ format: input.format, generation: input.generation, previous: input.previous,
		architecture: input.architecture, requested: input.requested, packages: input.packages }
	document_keys_schema(text, state_document_field, state_required_fields, state_value_type) or {
		close_decoded_state(state)
		return err
	}
	validate_state(state, architecture) or { close_decoded_state(state); return err }
	return state
}

// Only for independently owned JSON-decoded states. Plans and in-memory fixture
// states can share manifests; this is deliberately not a general State.close().
fn close_decoded_state(state State) {
	unsafe {
		state.architecture.free()
		for id in state.requested { id.free() }
		(&array(&state.requested)).free()
		for installed in state.packages {
			installed.repository.free(); installed.public_key.free()
			close_decoded_package(installed.package)
		}
		(&array(&state.packages)).free()
	}
}

fn numeric_generation_name(name string) bool {
	if name.len == 0 { return false }
	for byte in name { if byte < `0` || byte > `9` { return false } }
	return true
}

fn generation_number(name string) !u64 {
	if name.len == 0 || name.len > 20 || name[0] < `1` || name[0] > `9` {
		return error('invalid package generation identity: expected a canonical positive u64')
	}
	mut value := u64(0)
	for byte in name {
		if byte < `0` || byte > `9` { return error('invalid package generation identity: nondecimal name') }
		digit := u64(byte - `0`)
		if value > (~u64(0) - digit) / 10 { return error('package generation identity exceeds u64') }
		value = value * 10 + digit
	}
	return value
}

fn read_generation_state(directory string, architecture string, generation u64) !State {
	if generation == 0 { return error('invalid package generation identity: zero') }
	name := generation.str()
	path := directory + '/generations/' + name
	defer { unsafe { name.free(); path.free() } }
	if os.is_link(path) || !os.is_dir(path) {
		return error('package generation must be an ordinary directory')
	}
	metadata := path + '/state.json'
	defer { unsafe { metadata.free() } }
	text := read_metadata(metadata)!
	defer { unsafe { text.free() } }
	state := decode_persistent_state(text, architecture)!
	if state.generation != generation {
		close_decoded_state(state)
		return error('package generation identity mismatch')
	}
	return state
}

struct CollectionTarget {
	path string
	directory_device u64
	directory_inode u64
	lease_device u64
	lease_inode u64
}

struct CollectionLease {
	directory int
	lease int
	directory_device u64
	directory_inode u64
	lease_device u64
	lease_inode u64
}

fn close_collection_targets(targets []CollectionTarget) {
	for target in targets { unsafe { target.path.free() } }
	unsafe { (&array(&targets)).free() }
}

fn close_collection_lease(lease CollectionLease) {
	C.close(lease.lease)
	C.close(lease.directory)
}

fn open_collection_generation(path string) !CollectionLease {
	directory := C.open(path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if directory < 0 { return error('collection generation must be an ordinary directory') }
	mut folder := C.stat{}
	if C.fstat(directory, &folder) != 0 || u32(folder.st_mode) & 0o170000 != 0o040000 {
		C.close(directory)
		return error('cannot inspect collection generation')
	}
	// Nonblocking open prevents a malformed FIFO from hanging collection.
	lease := C.openat(directory, c'lease', C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if lease < 0 { C.close(directory); return error('cannot check generation lease before collection') }
	mut info := C.stat{}
	if C.fstat(lease, &info) != 0 || u32(info.st_mode) & 0o170000 != 0o100000 {
		C.close(lease)
		C.close(directory)
		return error('collection lease must be an ordinary regular file')
	}
	return CollectionLease{ directory: directory, lease: lease,
		directory_device: u64(folder.st_dev), directory_inode: u64(folder.st_ino),
		lease_device: u64(info.st_dev), lease_inode: u64(info.st_ino) }
}

// The caller holds the package writer lock, which excludes new launch admission.
// Check all names/leases before any removal, closing each descriptor pair before
// the next entry. Removal reopens the same filesystem identities and relocks;
// an existing holder that changes its lock state remains protected there too.
fn collection_targets(directory string, current State) ![]CollectionTarget {
	parent := directory + '/generations'
	defer { unsafe { parent.free() } }
	names := os.ls(parent)!
	defer { unsafe { for name in names { name.free() }; (&array(&names)).free() } }
	mut targets := []CollectionTarget{cap: names.len}
	mut admitted := false
	defer { if !admitted { close_collection_targets(targets) } }
	for name in names {
		if !numeric_generation_name(name) { continue }
		generation := generation_number(name)!
		if generation in [current.generation, current.previous]! { continue }
		path := parent + '/' + name
		lease := open_collection_generation(path) or {
			unsafe { path.free() }
			return err
		}
		if C.flock(lease.lease, C.LOCK_EX | C.LOCK_NB) != 0 {
			code := C.errno
			close_collection_lease(lease)
			unsafe { path.free() }
			if code == C.EWOULDBLOCK || code == C.EAGAIN { continue }
			return error('cannot lock generation lease before collection')
		}
		targets << CollectionTarget{ path: path, directory_device: lease.directory_device,
			directory_inode: lease.directory_inode, lease_device: lease.lease_device, lease_inode: lease.lease_inode }
		close_collection_lease(lease)
	}
	admitted = true
	return targets
}

fn remove_collection_target(target CollectionTarget) ! {
	lease := open_collection_generation(target.path)!
	defer { close_collection_lease(lease) }
	if lease.directory_device != target.directory_device || lease.directory_inode != target.directory_inode
		|| lease.lease_device != target.lease_device || lease.lease_inode != target.lease_inode {
		return error('collection generation or lease changed after preflight; retry collection')
	}
	if C.flock(lease.lease, C.LOCK_EX | C.LOCK_NB) != 0 {
		if C.errno == C.EWOULDBLOCK || C.errno == C.EAGAIN { return }
		return error('cannot lock generation lease for removal')
	}
	os.rmdir_all(target.path)!
}
