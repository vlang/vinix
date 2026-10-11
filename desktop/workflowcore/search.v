// SPDX-License-Identifier: GPL-2.0-or-later
module workflowcore

import os
import json2

pub struct SearchRoot {
pub:
	path string
	identity Identity
	network bool
	removable bool
pub mut:
	enabled bool
	contents bool
}

pub struct SearchRecord {
pub:
	path string
	identity Identity
	name string
	extension string
	content string
	tags []string
}

pub struct SearchIndex {
pub mut:
	roots []SearchRoot
	records []SearchRecord
	indexing bool
	limited bool
	denied int
mut:
	pending []string
	content_bytes int
}

pub fn (mut index SearchIndex) begin(roots []SearchRoot) {
	index.close()
	for root in roots {
		index.roots << SearchRoot{...root, path: root.path.clone()}
		if root.enabled { index.pending << root.path.clone() }
	}
	index.indexing = true
}

fn (index &SearchIndex) root_for(path string) ?SearchRoot {
	mut found := -1
	for i, root in index.roots {
		if inside_root(path, root.path) && (found < 0 || root.path.len > index.roots[found].path.len) { found = i }
	}
	if found < 0 { return none }
	root := index.roots[found]
	if !root.enabled { return none }
	if current := identify(root.path) { if root.identity.same_node(current) { return root } }
	return none
}

fn inside_root(path string, root string) bool {
	return path == root || (root == '/' && path.starts_with('/')) || (path.len > root.len && path.starts_with(root) && path[root.len] == `/`)
}

pub fn (mut index SearchIndex) tick() bool {
	if !index.indexing { return false }
	for _ in 0 .. 16 {
		if index.pending.len == 0 { index.indexing = false; break }
		path := index.pending.pop()
		defer { unsafe { path.free() } }
		root := index.root_for(path) or { continue }
		id := identify(path) or { index.denied++; continue }
		if id.device != root.identity.device || id.link() { continue }
		if C.access(&char(path.str), C.R_OK | if id.directory() { C.X_OK } else { 0 }) != 0 { index.denied++; continue }
		if id.directory() {
			if path != root.path {
				if index.records.len >= 100000 { index.limited = true; index.indexing = false; break }
				index.records << SearchRecord{path: path.clone(), identity: id, name: os.file_name(path).to_lower(), extension: '.folder'}
			}
			names := os.ls(path) or { index.denied++; continue }
			defer { unsafe { names.free() } }
			for name in names {
				if name.starts_with('.') { continue }
				if index.pending.len + index.records.len >= 100000 { index.limited = true; break }
				index.pending << os.join_path(path, name)
			}
			continue
		}
		if !id.regular() { continue }
		if index.records.len >= 100000 { index.limited = true; index.indexing = false; break }
		ext := os.file_ext(path).to_lower()
		mut content := ''
		if root.contents && id.size <= 256 * 1024 && index.content_bytes + int(id.size) <= 64 * 1024 * 1024 {
			if ext in ['.txt', '.md', '.v', '.c', '.h', '.json', '.csv', '.xml', '.html', '.log', '.ini', '.yaml', '.toml', '.rs', '.go', '.js', '.ts'] {
				if bytes := read_regular(path, 256 * 1024) {
				text := bytes.bytestr()
				if !text.contains('\x00') { content = text.to_lower(); index.content_bytes += content.len }
				unsafe { bytes.free(); text.free() }
				}
			} else if ext in ['.docx', '.xlsx', '.pptx', '.odt', '.ods', '.odp', '.epub', '.pdf'] {
				if preview := preview_document(path, '') {
					if preview.text.len <= 256 * 1024 && index.content_bytes + preview.text.len <= 64 * 1024 * 1024 { content = preview.text.to_lower(); index.content_bytes += content.len }
					unsafe { preview.text.free(); preview.image.free() }
				}
			}
		}
		index.records << SearchRecord{path: path.clone(), identity: id, name: os.file_name(path).to_lower(), extension: ext, content: content}
	}
	return true
}

// Recheck access, volume identity and file identity at query time. Revoked
// permissions and disconnected/replaced volumes cannot leak cached matches.
pub fn (index &SearchIndex) query(text string, limit int) []string {
	mut results := []string{}
	if text.len == 0 || limit < 1 { return results }
	query := text.to_lower()
	defer { unsafe { query.free() } }
	terms := query.split(' ')
	defer { unsafe { terms.free() } }
	for record in index.records {
		mut matches := true
		for term in terms {
			if term.len == 0 { continue }
			if term.starts_with('type:') { matches = record.extension.len == term.len - 4 && record.extension.ends_with(unsafe { tos(term.str + 5, term.len - 5) }) }
			else if term.starts_with('tag:') {
				matches = false
				for tag in record.tags { lower := tag.to_lower(); equal := lower == unsafe { tos(term.str + 4, term.len - 4) }; unsafe { lower.free() }; if equal { matches = true; break } }
			}
			else if term.starts_with('after:') { matches = record.identity.modified >= term[6..].i64() }
			else if term.starts_with('before:') { matches = record.identity.modified <= term[7..].i64() }
			else if term.starts_with('size:') { matches = record.identity.size >= term[5..].u64() }
			else { matches = record.name.contains(term) || (index.content_allowed(record.path) && record.content.contains(term)) }
			if !matches { break }
		}
		if !matches { continue }
		index.root_for(record.path) or { continue }
		if C.access(&char(record.path.str), C.R_OK | if record.identity.directory() { C.X_OK } else { 0 }) != 0 { continue }
		current := identify(record.path) or { continue }
		if !record.identity.unchanged(current) { continue }
		results << record.path.clone()
		if results.len >= limit { break }
	}
	return results
}

fn (index &SearchIndex) content_allowed(path string) bool {
	mut found := -1
	for i, root in index.roots { if inside_root(path, root.path) && (found < 0 || root.path.len > index.roots[found].path.len) { found = i } }
	return found >= 0 && index.roots[found].enabled && index.roots[found].contents
}

pub fn (mut index SearchIndex) set_tags(path string, tags []string) {
	for i, record in index.records {
		if record.path != path { continue }
		unsafe { index.records[i].tags.free() }
		index.records[i] = SearchRecord{...record, tags: tags.map(it.clone())}
		return
	}
}

pub fn (index &SearchIndex) save(home string) ! {
	store := private_store(home, '.vinix-search')!
	defer { unsafe { store.free() } }
	lock_fd := index_lock(store)!
	defer { C.close(lock_fd) }
	index.save_unlocked(store)!
}

fn index_lock(store string) !int {
	path := store + '/index.lock'
	defer { unsafe { path.free() } }
	fd := C.open(&char(path.str), C.O_RDWR | C.O_CREAT | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return error('index lock unavailable') }
	id := identify_fd(fd) or { C.close(fd); return err }
	if !id.regular() || id.uid != u32(C.getuid()) || id.mode & 0o077 != 0 || C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 { C.close(fd); return error('index busy; retry') }
	return fd
}

// A worker must honor policy changes made while it was scanning. Publish
// under the same lock as policy edits and remove newly excluded content.
pub fn (mut index SearchIndex) publish(home string) ! {
	store := private_store(home, '.vinix-search')!
	defer { unsafe { store.free() } }
	lock_fd := index_lock(store)!
	defer { C.close(lock_fd) }
	if previous := load_index(home) {
		mut latest := previous
		defer { latest.close() }
		for root in latest.roots {
			mut found := false
			for i, candidate in index.roots {
				if candidate.path != root.path { continue }
				index.roots[i].enabled = root.enabled
				index.roots[i].contents = root.contents
				found = true
				break
			}
			if !found { index.roots << SearchRoot{...root, path: root.path.clone()} }
		}
	}
	for i, record in index.records {
		if !index.content_allowed(record.path) { unsafe { index.records[i].content.free() }; index.records[i] = SearchRecord{...record, content: ''} }
	}
	index.save_unlocked(store)!
}

fn (index &SearchIndex) save_unlocked(store string) ! {
	text := json2.encode(index)
	bytes := text.bytes()
	defer { unsafe { text.free(); bytes.free() } }
	path := '${store}/index.json'
	defer { unsafe { path.free() } }
	atomic_save(path, bytes, SaveOptions{})!
}

pub fn load_index(home string) !SearchIndex {
	store := private_store(home, '.vinix-search')!
	defer { unsafe { store.free() } }
	path := '${store}/index.json'
	defer { unsafe { path.free() } }
	bytes := read_regular(path, 320 * 1024 * 1024)!
	text := bytes.bytestr()
	defer { unsafe { bytes.free(); text.free() } }
	mut index := json2.decode[SearchIndex](text)!
	if index.records.len > 100000 || index.roots.len > 256 { index.close(); return error('invalid search index') }
	index.indexing = false
	return index
}

pub fn (mut index SearchIndex) close() {
	for root in index.roots { unsafe { root.path.free() } }
	for r in index.records { unsafe { r.path.free(); r.name.free(); r.extension.free(); r.content.free(); r.tags.free() } }
	unsafe { index.roots.free(); index.records.free(); index.pending.free() }
	index = SearchIndex{}
}
