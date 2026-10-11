// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import math
import ui2
import desktop.workflowcore

struct FilesIndexedSearch {
mut:
	open bool
	index workflowcore.SearchIndex
	worker int
	query []u8
	results []string
	scroll int
	root_page int
	status string
}

fn files_service_home() string { return if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home } }

fn (mut a FilesContextApp) open_index_search() {
	a.index_search.open = true
	if a.index_search.index.roots.len > 0 { return }
	a.index_search.index = workflowcore.load_index(files_service_home()) or { workflowcore.SearchIndex{} }
	a.refresh_volumes()
	home := os.real_path(files_service_home())
	defer { unsafe { home.free() } }
	if a.index_search.index.roots.len == 0 {
		if id := workflowcore.identify(home) { a.index_search.index.roots << workflowcore.SearchRoot{path: home.clone(), identity: id, enabled: true, contents: true} }
	}
	for volume in a.volumes {
		if a.index_search.index.roots.any(it.path == volume.path) { continue }
		if id := workflowcore.identify(volume.path) { a.index_search.index.roots << workflowcore.SearchRoot{path: volume.path.clone(), identity: id, network: volume.network, removable: volume.removable} }
	}
	a.index_query()
}

fn (mut a FilesContextApp) index_query() {
	unsafe { a.index_search.results.free() }
	a.index_search.results = a.index_search.index.query(rename_buffer_text(a.index_search.query), 1000)
	a.index_search.scroll = 0
}

fn (mut a FilesContextApp) start_indexing() ! {
	if a.index_search.worker > 0 { return error('indexing is already running') }
	for i, root in a.index_search.index.roots {
		if root.enabled { if id := workflowcore.identify(root.path) { a.index_search.index.roots[i] = workflowcore.SearchRoot{...root, identity: id} } }
	}
	// Persist policy immediately, so the launcher stops returning an excluded
	// volume even while a new index is still being constructed.
	a.index_search.index.save(files_service_home())!
	pid := C.fork()
	if pid < 0 { return error('cannot start index worker') }
	if pid == 0 {
		for fd in 3 .. 1024 { C.close(fd) }
		mut index := workflowcore.SearchIndex{}
		index.begin(a.index_search.index.roots)
		for index.indexing { index.tick() }
		// Read tags after the scan so edits made during indexing are included.
		settings := load_files_settings(files_service_home())
		for path, ids in settings.assignments {
			mut tags := []string{}
			for id in ids { for tag in settings.tags { if tag.id == id { tags << tag.name.clone() } } }
			index.set_tags(path, tags)
			unsafe { tags.free() }
		}
		index.publish(files_service_home()) or { C._exit(1) }
		C._exit(0)
	}
	a.index_search.worker = pid
	unsafe { a.index_search.status.free() }
	a.index_search.status = 'Indexing in background. You can keep browsing.'.clone()
}

fn (mut a FilesContextApp) sync_index_tags(path string) {
	mut latest := workflowcore.load_index(files_service_home()) or { return }
	defer { latest.close() }
	mut tags := []string{}
	defer { unsafe { tags.free() } }
	ids := a.files.settings.assignments[path] or { []int{} }
	for id in ids { for tag in a.files.settings.tags { if tag.id == id { tags << tag.name.clone() } } }
	latest.set_tags(path, tags)
	latest.save(files_service_home()) or { a.operation_error('Could not update tag search; rebuild the index.'); return }
	a.index_search.index.set_tags(path, tags)
	if a.index_search.open { a.index_query() }
}

fn (mut a FilesContextApp) poll_index_search() bool {
	if a.index_search.worker <= 0 { return false }
	mut status := 0
	if C.waitpid(a.index_search.worker, unsafe { &status }, C.WNOHANG) != a.index_search.worker { return false }
	a.index_search.worker = 0
	unsafe { a.index_search.status.free() }
	if status != 0 { a.index_search.status = 'Indexing failed; previous results retained. Retry Rebuild.'.clone(); return true }
	a.index_search.index.close()
	a.index_search.index = workflowcore.load_index(files_service_home()) or {
		a.index_search.status = err.msg().clone()
		return true
	}
	a.index_search.status = '${a.index_search.index.records.len} files indexed; ${a.index_search.index.denied} inaccessible folders/files. ${if a.index_search.index.limited { 'Index limit reached.' } else { '' }}'
	a.index_query()
	return true
}

fn (mut a FilesContextApp) index_action(event string) bool {
	if event == 'files.index.open' { a.open_index_search(); return true }
	if !a.index_search.open { return false }
	if event == 'files.index.close' { a.index_search.open = false; return true }
	if event == 'files.index.rebuild' { a.start_indexing() or { unsafe { a.index_search.status.free() }; a.index_search.status = err.msg().clone() }; return true }
	if event == 'files.index.cancel' {
		if a.index_search.worker > 0 { C.kill(a.index_search.worker, C.SIGTERM) }
		return true
	}
	if event == 'files.index.roots.next' { a.index_search.root_page = (a.index_search.root_page + 1) % math.max(1, (a.index_search.index.roots.len + 3) / 4); return true }
	if event.starts_with('files.index.root.') || event.starts_with('files.index.contents.') {
		prefix := if event.starts_with('files.index.root.') { 'files.index.root.' } else { 'files.index.contents.' }
		i := event[prefix.len..].int()
		if i >= 0 && i < a.index_search.index.roots.len && a.index_search.worker == 0 {
			if prefix == 'files.index.root.' { a.index_search.index.roots[i].enabled = !a.index_search.index.roots[i].enabled }
			else { a.index_search.index.roots[i].contents = !a.index_search.index.roots[i].contents }
			a.index_search.index.save(files_service_home()) or {}
			a.index_query()
		}
		return true
	}
	if event.starts_with('files.index.row.') {
		i := event['files.index.row.'.len..].int()
		if i >= 0 && i < a.index_search.results.len {
			path := a.index_search.results[i].clone()
			a.index_search.open = false
			a.open_jump_path(path, files_service_home())
			unsafe { path.free() }
		}
		return true
	}
	return true
}

fn (mut a FilesContextApp) index_key(input string) {
	if input == '\x1b' { a.index_search.open = false; return }
	for ch in input {
		if ch in [u8(8), u8(127)] { if a.index_search.query.len > 0 { a.index_search.query.delete_last() } }
		else if ch >= 32 && a.index_search.query.len < 255 { a.index_search.query << ch }
	}
	a.index_query()
}

fn (a &FilesContextApp) index_panel(size ui2.Rect) ui2.Element {
	mut rows := frame_elements(40)
	for i, pair in [['files.index.close', 'Back']!, ['files.index.rebuild', 'Rebuild index']!, ['files.index.cancel', 'Cancel indexing']!, ['files.index.roots.next', 'More volumes']!]! {
		rows << ui2.button(pair[0], pair[1], ui2.rect(f64(8 + i * 140), 8, 132, 28), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 11})
	}
	rows << ui2.text_field('files.index.query', 'Names, contents, type:txt tag:Work size:1024 after:timestamp', rename_buffer_text(a.index_search.query), ui2.rect(8, 42, size.width - 16, 32), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 12}, 0)
	rows << ui2.label('', a.index_search.status, ui2.rect(8, 78, size.width - 16, 28), ui2.TextStyle{color: body_text, size: 11})
	for offset in 0 .. 4 {
		i := a.index_search.root_page * 4 + offset
		if i >= a.index_search.index.roots.len { break }
		root := a.index_search.index.roots[i]
		kind := if root.network { 'Network' } else if root.removable { 'Removable' } else { 'Local' }
		number := i.str()
		defer { unsafe { number.free() } }
		rows << workflow_button('files.index.root.' + number, '${if root.enabled { "✓" } else { "○" }} ${root.path} (${kind})', ui2.rect(8, f64(110 + offset * 30), size.width - 150, 28), true)
		rows << workflow_button('files.index.contents.' + number, if root.contents { 'Content: on' } else { 'Content: off' }, ui2.rect(size.width - 138, f64(110 + offset * 30), 130, 28), false)
	}
	visible := math.max(1, (int(size.height) - 240) / 30)
	for offset in 0 .. visible {
		i := a.index_search.scroll + offset
		if i >= a.index_search.results.len { break }
		number := i.str()
		defer { unsafe { number.free() } }
		rows << workflow_button('files.index.row.' + number, a.index_search.results[i], ui2.rect(8, f64(240 + offset * 30), size.width - 16, 28), false)
	}
	return ui2.screen(app_surface, rows)
}

fn (mut search FilesIndexedSearch) close() {
	if search.worker > 0 { C.kill(search.worker, C.SIGTERM); mut status := 0; C.waitpid(search.worker, unsafe { &status }, C.WNOHANG) }
	search.index.close()
	unsafe { search.query.free(); search.results.free(); search.status.free() }
	search = FilesIndexedSearch{}
}
