// SPDX-License-Identifier: GPL-2.0-or-later
module workflowcore

import os
import json2
import time
import crypto.sha256

pub struct Recovery {
pub:
	path string
	base ?Identity
	bytes []u8
	written i64
}

pub struct Document {
pub mut:
	path string
	expected ?Identity
mut:
	store string
	key string
}

pub fn private_store(home string, name string) !string {
	if home.len == 0 { return error('home unavailable') }
	if !name.starts_with('.vinix-') || name.contains('/') { return error('invalid store name') }
	root := os.real_path(home)
	defer { unsafe { root.free() } }
	if root == '' { return error('home unavailable') }
	store := os.join_path(root, name)
	if !os.exists(store) { os.mkdir(store, mode: 0o700) or { unsafe { store.free() }; return err } }
	id := identify(store) or { unsafe { store.free() }; return err }
	if !id.directory() || id.uid != u32(C.getuid()) || id.mode & 0o077 != 0 { unsafe { store.free() }; return error('private store permissions are unsafe') }
	return store
}

pub fn new_document(home string, path string) !Document {
	store := private_store(home, '.vinix-documents')!
	full := canonical(path) or { unsafe { store.free() }; return err }
	data := full.bytes()
	key := sha256.sum(data).hex()
	unsafe { data.free() }
	mut doc := Document{path: full, store: store, key: key}
	mut ready := false
	defer { if !ready { doc.close() } }
	for name in ['recovery', 'versions']! {
		dir := os.join_path(store, name)
		defer { unsafe { dir.free() } }
		if !os.exists(dir) { os.mkdir(dir, mode: 0o700)! }
		id := identify(dir)!
		if !id.directory() || id.uid != u32(C.getuid()) || id.mode & 0o077 != 0 { return error('document service directory unsafe') }
	}
	ready = true
	return doc
}

pub fn (mut doc Document) load(limit int) ![]u8 {
	before := identify(doc.path)!
	bytes := read_regular(doc.path, limit)!
	if !before.unchanged(identify(doc.path)!) { unsafe { bytes.free() }; return error('document changed while opening') }
	doc.expected = before
	return bytes
}

pub fn (mut doc Document) autosave(bytes []u8) ! {
	if bytes.len > 16 * 1024 * 1024 { return error('recovery document exceeds limit') }
	data := json2.encode(Recovery{path: doc.path, base: doc.expected, bytes: bytes, written: time.now().unix()})
	encoded := data.bytes()
	path := '${doc.store}/recovery/${doc.key}.json'
	defer { unsafe { data.free(); encoded.free(); path.free() } }
	atomic_save(path, encoded, SaveOptions{})!
}

pub fn (doc &Document) recovery() !Recovery {
	path := '${doc.store}/recovery/${doc.key}.json'
	defer { unsafe { path.free() } }
	bytes := read_regular(path, 80 * 1024 * 1024)!
	text := bytes.bytestr()
	defer { unsafe { bytes.free(); text.free() } }
	record := json2.decode[Recovery](text)!
	if record.path != doc.path || record.bytes.len > 16 * 1024 * 1024 { unsafe { record.path.free(); record.bytes.free() }; return error('invalid recovery record') }
	return record
}

pub fn (doc &Document) discard_recovery() ! {
	path := '${doc.store}/recovery/${doc.key}.json'
	defer { unsafe { path.free() } }
	if expected := identify(path) { remove_node(path, expected)! }
}

pub fn (doc &Document) versions() ![]string {
	mut result := []string{}
	directory := '${doc.store}/versions'
	prefix := doc.key + '.'
	defer { unsafe { directory.free(); prefix.free() } }
	names := os.ls(directory)!
	defer { unsafe { names.free() } }
	for name in names {
		if name.starts_with(prefix) && name.ends_with('.data') { result << name.clone() }
	}
	result.sort()
	return result
}

pub fn (doc &Document) version(name string, limit int) ![]u8 {
	prefix := doc.key + '.'
	path := '${doc.store}/versions/${name}'
	defer { unsafe { prefix.free(); path.free() } }
	if !name.starts_with(prefix) || name.contains('/') || !name.ends_with('.data') { return error('invalid document version') }
	return read_regular(path, limit)!
}

pub fn (mut doc Document) save(bytes []u8, create_only bool) ! {
	lock_path := '${doc.store}/${doc.key}.lock'
	defer { unsafe { lock_path.free() } }
	lock_fd := C.open(&char(lock_path.str), C.O_RDWR | C.O_CREAT | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0o600)
	if lock_fd < 0 { return error('document lock unavailable') }
	defer { C.close(lock_fd) }
	lock_identity := identify_fd(lock_fd)!
	if !lock_identity.regular() || lock_identity.uid != u32(C.getuid()) || lock_identity.mode & 0o077 != 0 || C.flock(lock_fd, C.LOCK_EX | C.LOCK_NB) != 0 { return error('document busy or lock unsafe; retry') }
	if create_only && item_exists(doc.path) { return error('destination exists') }
	if old := doc.expected {
		if !old.unchanged(identify(doc.path)!) { return error('document changed on disk; reload or Save As') }
		previous := read_regular(doc.path, 16 * 1024 * 1024)!
		defer { unsafe { previous.free() } }
		version := '${doc.store}/versions/${doc.key}.${time.now().unix_micro():020}.${os.getpid()}.data'
		defer { unsafe { version.free() } }
		atomic_save(version, previous, SaveOptions{create_only: true})!
	}
	doc.expected = atomic_save(doc.path, bytes, SaveOptions{expected: doc.expected, create_only: create_only})!
	doc.discard_recovery()!
	versions := doc.versions()!
	defer { unsafe { versions.free() } }
	if versions.len > 32 {
		for name in versions[..versions.len - 32] {
			path := '${doc.store}/versions/${name}'
			defer { unsafe { path.free() } }
			if id := identify(path) { remove_node(path, id)! }
		}
	}
}

pub fn (mut doc Document) close() {
	unsafe { doc.path.free(); doc.store.free(); doc.key.free() }
	doc = Document{}
}
