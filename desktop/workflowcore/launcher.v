// SPDX-License-Identifier: GPL-2.0-or-later
module workflowcore

import os

// Launcher queries favor folders while retaining the document search syntax.
// The desktop calls this in a worker: loading an index and checking filesystem
// permissions must never delay its application results or keyboard handling.
pub fn (index &SearchIndex) launcher_query(text string, home string, limit int) []string {
	mut results := []string{}
	if limit < 1 { return results }
	trimmed := text.trim_space()
	defer { unsafe { trimmed.free() } }
	if trimmed.len == 0 { return results }
	launcher_path_suggestions(trimmed, home, limit, mut results)
	if results.len >= limit { return results }
	query := trimmed.to_lower()
	terms := query.split(' ')
	defer { unsafe { query.free(); terms.free() } }
	mut plain := true
	for term in terms {
		if term.starts_with('type:') || term.starts_with('tag:') || term.starts_with('after:') || term.starts_with('before:') || term.starts_with('size:') {
			plain = false
			break
		}
	}
	if plain {
		if index.roots.len == 0 && !trimmed.starts_with('/') && !trimmed.starts_with('~/') && trimmed != '~' {
			launcher_home_folders(home, terms, limit, mut results)
			if results.len >= limit { return results }
		}
		// Roots are deliberately absent from the document index, but users must
		// still be able to find their home or another configured search root.
		for root in index.roots {
			if !launcher_folder_matches(root.path, terms) { continue }
			index.root_for(root.path) or { continue }
			if launcher_directory(root.path) { launcher_append_path(root.path, limit, mut results) }
			if results.len >= limit { return results }
		}
		for record in index.records {
			if !record.identity.directory() || !launcher_folder_matches(record.path, terms) { continue }
			index.root_for(record.path) or { continue }
			current := identify(record.path) or { continue }
			// Adding or removing a child changes a directory's timestamps, not
			// its identity. Replacing the directory invalidates the old record.
			if !record.identity.same_node(current) || !current.directory() || C.access(&char(record.path.str), C.R_OK | C.X_OK) != 0 { continue }
			launcher_append_path(record.path, limit, mut results)
			if results.len >= limit { return results }
		}
	}
	// One shared query preserves content, tags, filters and permission policy.
	// Request enough rows to cover folders already placed before documents.
	documents := index.query(trimmed, limit + results.len)
	defer { unsafe { documents.free() } }
	for path in documents {
		launcher_append_path(path, limit, mut results)
		if results.len >= limit { break }
	}
	return results
}

fn launcher_append_path(path string, limit int, mut results []string) {
	if results.len >= limit { return }
	for previous in results { if previous == path { return } }
	results << path.clone()
}

fn launcher_directory(path string) bool {
	if path != '/' && !valid_path(path) { return false }
	identity := identify(path) or { return false }
	return identity.directory() && C.access(&char(path.str), C.R_OK | C.X_OK) == 0
}

fn launcher_folder_matches(path string, terms []string) bool {
	lower := path.to_lower()
	defer { unsafe { lower.free() } }
	for term in terms {
		if term.len > 0 && !lower.contains(term) { return false }
	}
	return true
}

// A first launch has no saved index yet. Search directory names without
// waiting for document content extraction, visiting shallow folders first.
// Configured roots, including disabled roots, never use this fallback.
fn launcher_home_folders(home string, terms []string, limit int, mut results []string) {
	if !launcher_directory(home) { return }
	root := identify(home) or { return }
	if launcher_folder_matches(home, terms) { launcher_append_path(home, limit, mut results) }
	if results.len >= limit { return }
	mut pending := []string{cap: 8192}
	unsafe { pending.flags |= .noslices }
	defer { unsafe { pending.free() } }
	pending << home.clone()
	mut at := 0
	mut entries := 0
	for at < pending.len && entries < 100000 {
		parent := pending[at]
		at++
		names := os.ls(parent) or { continue }
		defer { unsafe { names.free() } }
		for name in names {
			if entries >= 100000 { return }
			entries++
			if name.starts_with('.') { continue }
			child := os.join_path(parent, name)
			defer { unsafe { child.free() } }
			identity := identify(child) or { continue }
			if !identity.directory() || identity.device != root.device || C.access(&char(child.str), C.R_OK | C.X_OK) != 0 { continue }
			if launcher_folder_matches(child, terms) { launcher_append_path(child, limit, mut results) }
			if results.len >= limit { return }
			if pending.len < 8192 { pending << child.clone() }
		}
	}
}

// An explicit path searches its parent directly, including locations outside
// background indexing roots. It only exposes accessible, real directories.
fn launcher_path_suggestions(text string, home string, limit int, mut results []string) {
	mut expanded := ''
	if text.starts_with('/') {
		expanded = text.clone()
	} else if text == '~' && home.len > 0 {
		expanded = home.clone()
	} else if text.starts_with('~/') && home.len > 0 {
		tail := unsafe { tos(text.str + 2, text.len - 2) }
		expanded = os.join_path(home, tail)
	} else { return }
	defer { unsafe { expanded.free() } }
	path := os.norm_path(expanded)
	defer { unsafe { path.free() } }
	if !path.starts_with('/') || (path != '/' && !valid_path(path)) { return }
	if launcher_directory(path) { launcher_append_path(path, limit, mut results) }
	if results.len >= limit { return }
	parent := if text.ends_with('/') { path.clone() } else { os.dir(path) }
	leaf := os.file_name(path)
	prefix := if text.ends_with('/') { '' } else { leaf.to_lower() }
	defer { unsafe { parent.free(); leaf.free(); prefix.free() } }
	if !launcher_directory(parent) { return }
	names := os.ls(parent) or { return }
	defer { unsafe { names.free() } }
	for name in names {
		lower := name.to_lower()
		matches := lower.starts_with(prefix)
		unsafe { lower.free() }
		if !matches || (name.starts_with('.') && !prefix.starts_with('.')) { continue }
		child := os.join_path(parent, name)
		defer { unsafe { child.free() } }
		if launcher_directory(child) { launcher_append_path(child, limit, mut results) }
		if results.len >= limit { break }
	}
}
