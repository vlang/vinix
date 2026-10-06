// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn archive_memory_root(name string) string {
	temporary := os.real_path(os.temp_dir())
	root := '${temporary}/vinix-archive-${name}-${os.getpid()}'
	unsafe { temporary.free() }
	os.rmdir_all(root) or {}
	os.mkdir(root) or { panic(err) }
	return root
}

fn archive_memory_finish(mut app ArchiveApp) {
	for _ in 0 .. 4096 {
		if app.operation == .idle { return }
		app.poll()
	}
	panic('Archive fixture exceeded operation bound')
}

fn test_archive_full_workflows_and_frames_release_owned_memory() {
	root := archive_memory_root('owned-heap')
	defer {
		os.rmdir_all(root) or {}
		unsafe { root.free() }
	}
	source := join_path(root, 'source.txt')
	output := join_path(root, 'output.tar')
	destination := join_path(root, 'destination')
	defer {
		unsafe {
			source.free()
			output.free()
			destination.free()
		}
	}
	os.write_file(source, 'Hello 日本語 😀\n')!
	rootfd := archive_open_source(root)
	assert rootfd >= 0
	defer { desktop_close(rootfd) }
	// Warm translations, shared frame storage and the bounded recent-items
	// cache outside tracking, then track every app-owned allocation below.
	mut warm := new_archive_app()
	archive_set_field(mut warm.source_input, source)
	archive_set_field(mut warm.output_input, output)
	assert warm.create_archive()
	archive_memory_finish(mut warm)
	archive_set_field(mut warm.archive_input, output)
	assert warm.browse_archive()
	archive_memory_finish(mut warm)
	begin_frame_elements()
	warm_tree := warm.build(ui2.rect(0, 0, 800, 680))!
	free_tree(warm_tree)
	warm.close_app()
	assert C.unlinkat(rootfd, c'output.tar', 0) == 0
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := new_archive_app()
		archive_set_field(mut app.source_input, source)
		archive_set_field(mut app.output_input, output)
		assert app.create_archive()
		archive_memory_finish(mut app)
		assert app.status_key == 'archive.created'
		archive_set_field(mut app.archive_input, output)
		assert app.browse_archive()
		archive_memory_finish(mut app)
		assert app.status_key == 'archive.loaded'
		archive_set_field(mut app.extract_input, destination)
		assert app.extract_archive()
		archive_memory_finish(mut app)
		assert app.status_key == 'archive.extracted'
		app.focus_field(0)
		app.key_input('\x01')
		app.paste_input('/日本語/😀.tar')
		app.key_input('\x7f')
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 800, 680))!
		free_tree(tree)
		app.close_app()
		app.close_app()
		assert C.unlinkat(rootfd, c'output.tar', 0) == 0
		extractfd := C.openat(rootfd, c'destination', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
		assert extractfd >= 0
		assert C.unlinkat(extractfd, c'source.txt', 0) == 0
		assert desktop_close(extractfd) == 0
		assert C.unlinkat(rootfd, c'destination', C.AT_REMOVEDIR) == 0
	}
	assert C.vinix_heap_end() == 0
}

fn test_archive_cancel_rejection_and_entry_array_growth_release_owned_memory() {
	root := archive_memory_root('heap-growth')
	defer {
		os.rmdir_all(root) or {}
		unsafe { root.free() }
	}
	path := join_path(root, 'many.tar')
	defer { unsafe { path.free() } }
	mut data := []u8{cap: 512 * 300 + 1024}
	for index in 0 .. 300 {
		number := index.str()
		name := 'file-${number}.txt'
		header := archive_tar_header(ArchiveEntry{ name: name })
		for byte in header { data << byte }
		unsafe {
			number.free()
			name.free()
		}
	}
	for _ in 0 .. 1024 { data << u8(0) }
	os.write_file_array(path, data)!
	unsafe { data.free() }
	// The recent-items cache owns its one persistent path; warm it first.
	mut warm := new_archive_app()
	archive_set_field(mut warm.archive_input, path)
	assert warm.browse_archive()
	archive_memory_finish(mut warm)
	begin_frame_elements()
	warm_tree := warm.build(ui2.rect(0, 0, 800, 680))!
	free_tree(warm_tree)
	warm.close_app()
	C.vinix_heap_begin()
	for _ in 0 .. 25 {
		mut app := new_archive_app()
		archive_set_field(mut app.archive_input, path)
		assert app.browse_archive()
		app.poll()
		app.cancel()
		assert app.data.len == 0
		assert app.browse_archive()
		archive_memory_finish(mut app)
		assert app.entries.len == 300
		app.key_input('\x1b[6~')
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 800, 680))!
		free_tree(tree)
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

fn archive_memory_fd_count() int {
	mut total := 0
	for fd in 0 .. 1024 { if C.fcntl(fd, C.F_GETFD) >= 0 { total++ } }
	return total
}

fn test_archive_recursive_creation_releases_directory_buffers_and_descriptors() {
	root := archive_memory_root('tree-heap')
	defer {
		os.rmdir_all(root) or {}
		unsafe { root.free() }
	}
	source := join_path(root, 'documents')
	nested := join_path(source, 'nested')
	output := join_path(root, 'tree.tar')
	defer { unsafe {
		source.free()
		nested.free()
		output.free()
	}
	 }
	os.mkdir_all(nested)!
	os.write_file(join_path(source, 'file.txt'), 'one')!
	os.write_file(join_path(nested, '日本語.txt'), 'two 😀')!
	rootfd := archive_open_source(root)
	assert rootfd >= 0
	defer { desktop_close(rootfd) }
	before := archive_memory_fd_count()
	C.vinix_heap_begin()
	for _ in 0 .. 50 {
		mut app := new_archive_app()
		archive_set_field(mut app.source_input, source)
		archive_set_field(mut app.output_input, output)
		assert app.create_archive() && app.entries.len == 4
		archive_memory_finish(mut app)
		assert app.status_key == 'archive.created'
		app.close_app()
		assert C.unlinkat(rootfd, c'tree.tar', 0) == 0
	}
	assert C.vinix_heap_end() == 0
	assert archive_memory_fd_count() == before
}

fn archive_memory_remove_selection(rootfd int) {
	extractfd := C.openat(rootfd, c'selected', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	assert extractfd >= 0
	docsfd := C.openat(extractfd, c'docs', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	assert docsfd >= 0
	assert C.unlinkat(docsfd, c'日本語.txt', 0) == 0
	assert desktop_close(docsfd) == 0
	assert C.unlinkat(extractfd, c'docs', C.AT_REMOVEDIR) == 0
	assert desktop_close(extractfd) == 0
	assert C.unlinkat(rootfd, c'selected', C.AT_REMOVEDIR) == 0
}

fn test_archive_selection_repeated_frames_wire_extract_cancel_refresh_and_reject_keep_zero_bytes() {
	root := archive_memory_root('selection-heap')
	defer {
		os.rmdir_all(root) or {}
		unsafe { root.free() }
	}
	path := join_path(root, 'choices.tar')
	destination := join_path(root, 'selected')
	defer { unsafe { path.free() destination.free() } }
	mut data := []u8{cap: 4096}
	for index, name in ['omit.txt', 'docs', 'docs/日本語.txt', 'docs-extra/else.txt'] {
		payload := if index == 2 { 'chosen 😀' } else { '' }
		header := archive_tar_header(ArchiveEntry{name: name, size: u64(payload.len), directory: index == 1})
		for byte in header { data << byte }
		for byte in payload { data << byte }
		for _ in 0 .. (512 - payload.len % 512) % 512 { data << u8(0) }
	}
	for _ in 0 .. 1024 { data << u8(0) }
	os.write_file_array(path, data)!
	unsafe { data.free() }
	rootfd := archive_open_source(root)
	assert rootfd >= 0
	defer { desktop_close(rootfd) }
	mut warm := new_archive_app()
	archive_set_field(mut warm.archive_input, path)
	assert warm.browse_archive()
	archive_memory_finish(mut warm)
	begin_frame_elements()
	warm_tree := warm.build(ui2.rect(0, 0, 800, 680))!
	free_tree(warm_tree)
	warm.close_app()
	before := archive_memory_fd_count()
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut app := new_archive_app()
		archive_set_field(mut app.archive_input, path)
		archive_set_field(mut app.extract_input, destination)
		assert app.browse_archive()
		archive_memory_finish(mut app)
		assert !app.extract_selection() && app.status_key == 'archive.no_selection'
		app.handle('archive.row.1')!
		assert app.entries[1].selected && app.entries[2].selected && !app.entries[3].selected
		for _ in 0 .. 3 {
			begin_frame_elements()
			tree := app.build(ui2.rect(0, 0, 800, 680))!
			mut encoded := []u8{cap: 4096}
			unsafe { encoded.flags |= .noslices }
			encode_app_element(tree, mut encoded)!
			decoded := decode_app_tree(encoded)!
			free_tree(decoded)
			free_tree(tree)
			unsafe { encoded.free() }
		}
		assert app.extract_selection()
		archive_memory_finish(mut app)
		assert app.status_key == 'archive.extracted' && app.done == app.goal
		assert !app.extract_selection() && app.status_key == 'archive.exists'
		archive_memory_remove_selection(rootfd)
		assert app.extract_selection()
		assert app.poll() && app.done == 0
		assert app.poll() && app.done == 0
		assert app.poll() && app.done == u64('chosen 😀'.len)
		app.cancel()
		assert app.status_key == 'archive.cancelled_partial'
		archive_memory_remove_selection(rootfd)
		app.handle('archive.select_all')!
		app.handle('archive.clear_selection')!
		assert !app.extract_selection() && app.status_key == 'archive.no_selection'
		assert app.browse_archive()
		archive_memory_finish(mut app)
		for entry in app.entries { assert !entry.selected }
		app.close_app()
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
	assert archive_memory_fd_count() == before
}
