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
	if !name.starts_with('.vinix-') || name.contains('/') { return error('invalid store name') }
	root := os.real_path(home)
	if root == '' { return error('home unavailable') }
	store := os.join_path(root, name)
	if !os.exists(store) { os.mkdir(store, mode: 0o700)! }
	id := identify(store)!
	if !id.directory() || id.uid != u32(C.getuid()) || id.mode & 0o077 != 0 { return error('private store permissions are unsafe') }
	return store
}

pub fn new_document(home string, path string) !Document {
	store := private_store(home, '.vinix-documents')!
	full := canonical(path)!
	key := sha256.sum(full.bytes()).hex()
	for name in ['recovery', 'versions'] {
		dir := os.join_path(store, name)
		if !os.exists(dir) { os.mkdir(dir, mode: 0o700)! }
		id := identify(dir)!
		if !id.directory() || id.uid != u32(C.getuid()) || id.mode & 0o077 != 0 { return error('document service directory unsafe') }
	}
	return Document{path: full, store: store, key: key}
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
	defer { unsafe { data.free() } }
	atomic_save('${doc.store}/recovery/${doc.key}.json', data.bytes(), SaveOptions{})!
}

pub fn (doc &Document) recovery() !Recovery {
	bytes := read_regular('${doc.store}/recovery/${doc.key}.json', 80 * 1024 * 1024)!
	defer { unsafe { bytes.free() } }
	record := json2.decode[Recovery](bytes.bytestr())!
	if record.path != doc.path || record.bytes.len > 16 * 1024 * 1024 { return error('invalid recovery record') }
	return record
}

pub fn (doc &Document) discard_recovery() ! {
	path := '${doc.store}/recovery/${doc.key}.json'
	if expected := identify(path) { remove_node(path, expected)! }
}

pub fn (doc &Document) versions() ![]string {
	mut result := []string{}
	for name in os.ls('${doc.store}/versions')! {
		if name.starts_with(doc.key + '.') && name.ends_with('.data') { result << name }
	}
	result.sort()
	return result
}

pub fn (doc &Document) version(name string, limit int) ![]u8 {
	if !name.starts_with(doc.key + '.') || name.contains('/') || !name.ends_with('.data') { return error('invalid document version') }
	return read_regular('${doc.store}/versions/${name}', limit)!
}

pub fn (mut doc Document) save(bytes []u8, create_only bool) ! {
	if old := doc.expected {
		if !old.unchanged(identify(doc.path)!) { return error('document changed on disk; reload or Save As') }
		previous := read_regular(doc.path, 16 * 1024 * 1024)!
		defer { unsafe { previous.free() } }
		version := '${doc.store}/versions/${doc.key}.${time.now().unix_micro():020}.${os.getpid()}.data'
		atomic_save(version, previous, SaveOptions{create_only: true})!
	}
	doc.expected = atomic_save(doc.path, bytes, SaveOptions{expected: doc.expected, create_only: create_only})!
	doc.discard_recovery()!
	versions := doc.versions()!
	defer { unsafe { versions.free() } }
	if versions.len > 32 {
		for name in versions[..versions.len - 32] {
			path := '${doc.store}/versions/${name}'
			if id := identify(path) { remove_node(path, id)! }
		}
	}
}

pub fn (mut doc Document) close() {
	unsafe { doc.path.free(); doc.store.free(); doc.key.free() }
	doc = Document{}
}
