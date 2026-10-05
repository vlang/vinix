// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn C.mkfifo(path &char, mode u32) int

fn archive_test_root(name string) string {
	// Darwin /var and /tmp are symlinks; the application intentionally rejects
	// all symlink ancestors, so fixtures use the resolved ordinary directory.
	temporary := os.real_path(os.temp_dir())
	root := '${temporary}/vinix-archive-${name}-${os.getpid()}'
	unsafe { temporary.free() }
	os.rmdir_all(root) or {}
	os.mkdir(root) or { panic(err) }
	return root
}

fn archive_test_header_checksum(mut header [512]u8) {
	for at in 148 .. 156 { header[at] = ` ` }
	mut sum := u64(0)
	for byte in header { sum += u64(byte) }
	archive_put_octal(mut header, 148, 8, sum)
}

fn archive_test_single(name string, payload string, kind u8) []u8 {
	mut header := archive_tar_header(ArchiveEntry{ name: name, size: u64(payload.len), directory: kind == `5` })
	header[156] = kind
	archive_test_header_checksum(mut header)
	mut data := []u8{cap: 512 + ((payload.len + 511) / 512) * 512 + 1024}
	unsafe { data.flags |= .noslices }
	for byte in header { data << byte }
	for byte in payload { data << byte }
	for _ in 0 .. (512 - payload.len % 512) % 512 { data << u8(0) }
	for _ in 0 .. 1024 { data << u8(0) }
	return data
}

fn archive_test_finish(mut app ArchiveApp) {
	for _ in 0 .. 4096 {
		if app.operation == .idle { return }
		assert app.poll()
	}
	panic('Archive operation exceeded its bounded fixture deadline')
}

fn archive_test_write(path string, name string, payload string) {
	data := archive_test_single(name, payload, `0`)
	os.write_file_array(path, data) or { panic(err) }
	unsafe { data.free() }
}

fn archive_test_action(tree ui2.Element, id string) bool {
	if tree.id == id { return true }
	for child in tree.children { if archive_test_action(child, id) { return true } }
	return false
}

fn test_archive_round_trip_creates_browses_and_extracts_a_real_tree() {
	root := archive_test_root('round-trip')
	defer { os.rmdir_all(root) or {} }
	source := join_path(root, 'documents')
	subfolder := join_path(source, 'nested')
	os.mkdir_all(subfolder)!
	os.write_file(join_path(source, 'empty.txt'), '')!
	os.write_file(join_path(subfolder, '日本語.txt'), 'Hello 😀\n')!
	output := join_path(root, 'documents.tar')
	destination := join_path(root, 'extracted')
	mut app := new_archive_app()
	defer { app.close_app() }
	archive_set_field(mut app.source_input, source)
	archive_set_field(mut app.output_input, output)
	assert app.create_archive()
	assert app.operation == .creating && app.entries.len == 4
	assert app.next_poll_ms() == 16
	archive_test_finish(mut app)
	assert app.status_key == 'archive.created' && app.done == app.goal
	assert app.next_poll_ms() == 2000
	assert !app.create_archive() && app.status_key == 'archive.exists'
	archive_set_field(mut app.archive_input, output)
	assert app.browse_archive()
	archive_test_finish(mut app)
	assert app.status_key == 'archive.loaded' && app.entries.len == 4
	assert app.data_size == u64('Hello 😀\n'.len)
	archive_set_field(mut app.extract_input, destination)
	assert app.extract_archive()
	archive_test_finish(mut app)
	assert app.status_key == 'archive.extracted'
	assert os.read_file(join_path(destination, 'documents/nested/日本語.txt'))! == 'Hello 😀\n'
	assert os.read_file(join_path(destination, 'documents/empty.txt'))! == ''
	assert !app.extract_archive() && app.status_key == 'archive.exists'
	assert !app.poll()
}

fn test_archive_snapshot_survives_source_replacement_and_shortened_fields() {
	root := archive_test_root('snapshot')
	defer { os.rmdir_all(root) or {} }
	path := join_path(root, 'a.tar')
	long_path := join_path(root, 'a.tar.long')
	archive_test_write(path, 'file.txt', 'captured')
	archive_test_write(long_path, 'wrong.txt', 'wrong')
	mut app := new_archive_app()
	defer { app.close_app() }
	archive_set_field(mut app.archive_input, long_path)
	app.focus_field(0)
	app.key_input('\x01')
	app.paste_input(path)
	assert app.browse_archive()
	archive_test_finish(mut app)
	assert app.loaded_path == path && app.entries[0].name == 'file.txt'
	os.write_file(path, 'the original was modified after Browse')!
	destination := join_path(root, 'out')
	archive_set_field(mut app.extract_input, destination)
	assert app.extract_archive()
	archive_test_finish(mut app)
	assert os.read_file(join_path(destination, 'file.txt'))! == 'captured'
	assert app.status_key == 'archive.extracted'
}

fn test_archive_rejects_traversal_links_special_types_and_conflicting_entries() {
	mut entries := []ArchiveEntry{}
	defer {
		archive_free_entries(mut entries)
		unsafe { entries.free() }
	}
	for name in ['/absolute', '../escape', 'nested/../../escape', 'nested//file', './file',
		'nested/./file', 'nested/../file', 'back\\slash', 'bad\x00name', 'bad\nname', 'invalid\xff'] {
		mut data := archive_test_single('safe', 'payload', `0`)
		mut header := [512]u8{}
		for at in 0 .. 512 { header[at] = data[at] }
		for at in 0 .. 100 { header[at] = 0 }
		for at, byte in name { header[at] = byte }
		archive_test_header_checksum(mut header)
		for at in 0 .. 512 { data[at] = header[at] }
		_, status := archive_parse_tar(data, mut entries)
		// NUL ends a TAR name, so an embedded suffix is not part of the path.
		if name == 'bad\x00name' {
			assert status == '' && entries[0].name == 'bad'
		} else {
			assert status == 'archive.unsafe_entry'
		}
		unsafe { data.free() }
	}
	for kind in [u8(`1`), `2`, `3`, `4`, `6`, `7`, `x`, `g`, `L`, `K`] {
		data := archive_test_single('entry', '', kind)
		_, status := archive_parse_tar(data, mut entries)
		assert status == 'archive.unsafe_entry'
		unsafe { data.free() }
	}
	first := archive_test_single('file', 'one', `0`)
	second := archive_test_single('file/child', 'two', `0`)
	mut data := []u8{cap: first.len + second.len}
	for at in 0 .. first.len - 1024 { data << first[at] }
	for byte in second { data << byte }
	_, status := archive_parse_tar(data, mut entries)
	assert status == 'archive.unsafe_entry'
	unsafe {
		first.free()
		second.free()
		data.free()
	}
	duplicate := archive_test_single('same', '', `5`)
	mut duplicated := []u8{cap: duplicate.len + 512}
	for at in 0 .. 512 { duplicated << duplicate[at] }
	for byte in duplicate { duplicated << byte }
	_, repeated_status := archive_parse_tar(duplicated, mut entries)
	assert repeated_status == 'archive.unsafe_entry'
	unsafe {
		duplicate.free()
		duplicated.free()
	}
}

fn test_archive_validates_checksum_sizes_end_blocks_and_formats() {
	mut entries := []ArchiveEntry{}
	defer {
		archive_free_entries(mut entries)
		unsafe { entries.free() }
	}
	mut data := archive_test_single('file.txt', 'text', `0`)
	defer { unsafe { data.free() } }
	data[0] ^= 1
	_, checksum_status := archive_parse_tar(data, mut entries)
	assert checksum_status == 'archive.invalid_tar'
	data[0] ^= 1
	data.trim(data.len - 512)
	_, missing_end := archive_parse_tar(data, mut entries)
	assert missing_end == 'archive.invalid_tar'
	for _ in 0 .. 512 { data << u8(0) }
	data[data.len - 1] = 1
	_, trailer := archive_parse_tar(data, mut entries)
	assert trailer == 'archive.invalid_tar'
	data[data.len - 1] = 0
	mut header := [512]u8{}
	for at in 0 .. 512 { header[at] = data[at] }
	archive_put_octal(mut header, 124, 12, u64(archive_max_bytes) + 1)
	archive_test_header_checksum(mut header)
	for at in 0 .. 512 { data[at] = header[at] }
	_, size_status := archive_parse_tar(data, mut entries)
	assert size_status == 'archive.invalid_tar'
	gz := [u8(0x1f), 0x8b, 0x08]
	zip := [u8(`P`), `K`, 3, 4]
	_, gzip_status := archive_parse_tar(gz, mut entries)
	_, zip_status := archive_parse_tar(zip, mut entries)
	assert gzip_status == 'archive.unsupported' && zip_status == 'archive.unsupported'
	empty := []u8{len: 1024}
	total, empty_status := archive_parse_tar(empty, mut entries)
	assert total == 0 && empty_status == '' && entries.len == 0
	unsafe {
		gz.free()
		zip.free()
		empty.free()
	}
}

fn test_archive_rejects_symlink_ancestors_and_extraction_member_replacement() {
	root := archive_test_root('symlink')
	defer { os.rmdir_all(root) or {} }
	path := join_path(root, 'safe.tar')
	archive_test_write(path, 'nested/file.txt', 'safe content')
	outside := join_path(root, 'outside')
	os.mkdir(outside)!
	marker := join_path(outside, 'file.txt')
	os.write_file(marker, 'must survive')!
	alias := join_path(root, 'alias')
	os.symlink(root, alias)!
	mut app := new_archive_app()
	defer { app.close_app() }
	archive_set_field(mut app.archive_input, join_path(alias, 'safe.tar'))
	assert !app.browse_archive() && app.status_key == 'archive.read_failed'
	archive_set_field(mut app.archive_input, path)
	assert app.browse_archive()
	archive_test_finish(mut app)
	archive_set_field(mut app.extract_input, join_path(alias, 'new-folder'))
	assert !app.extract_archive()
	assert !os.exists(join_path(root, 'new-folder'))
	destination := join_path(root, 'extract')
	archive_set_field(mut app.extract_input, destination)
	assert app.extract_archive()
	os.symlink(outside, join_path(destination, 'nested'))!
	archive_test_finish(mut app)
	assert app.status_key == 'archive.extract_failed'
	assert os.read_file(marker)! == 'must survive'
	archive_set_field(mut app.source_input, alias)
	archive_set_field(mut app.output_input, join_path(root, 'link-source.tar'))
	assert !app.create_archive() && app.status_key == 'archive.read_failed'
	os.symlink(outside, join_path(outside, 'nested-link'))!
	archive_set_field(mut app.source_input, outside)
	assert !app.create_archive() && app.status_key == 'archive.unsafe_entry'
	assert !os.exists(join_path(root, 'link-source.tar'))
}

fn test_archive_payload_work_is_bounded_and_cancel_cleans_only_partial_tar() {
	root := archive_test_root('cancel')
	defer { os.rmdir_all(root) or {} }
	payload := 'a'.repeat(archive_chunk * 3 + 17)
	defer { unsafe { payload.free() } }
	source := join_path(root, 'large.txt')
	output := join_path(root, 'large.tar')
	os.write_file(source, payload)!
	mut app := new_archive_app()
	defer { app.close_app() }
	archive_set_field(mut app.source_input, source)
	archive_set_field(mut app.output_input, output)
	assert app.create_archive()
	assert app.poll()
	assert app.entry_written == u64(archive_chunk)
	app.key_input('\x1b')
	assert app.status_key == 'archive.cancelled' && app.operation == .idle
	assert !os.exists(output) && os.read_file(source)! == payload
	assert app.create_archive()
	archive_test_finish(mut app)
	archive_set_field(mut app.archive_input, output)
	assert app.browse_archive()
	assert app.poll() && app.done == u64(archive_chunk)
	app.cancel()
	assert app.data.len == 0 && app.loaded_path.len == 0 && app.read_fd == -1
	assert app.browse_archive()
	archive_test_finish(mut app)
	destination := join_path(root, 'partial')
	archive_set_field(mut app.extract_input, destination)
	assert app.extract_archive()
	assert app.poll() && app.done == u64(archive_chunk)
	app.cancel()
	assert app.status_key == 'archive.cancelled_partial'
	assert os.read_file(join_path(destination, 'large.txt'))!.len == archive_chunk
	assert os.read_file(source)! == payload
	assert app.read_fd == -1 && app.root_fd == -1 && app.write_fd == -1 && app.output_parent == -1
}

fn test_archive_detects_changed_source_and_refuses_nonregular_or_large_files() {
	root := archive_test_root('source-limits')
	defer { os.rmdir_all(root) or {} }
	source := join_path(root, 'source.txt')
	output := join_path(root, 'output.tar')
	os.write_file(source, 'original')!
	mut app := new_archive_app()
	defer { app.close_app() }
	archive_set_field(mut app.source_input, source)
	archive_set_field(mut app.output_input, output)
	assert app.create_archive()
	os.write_file(source, 'changed to a longer file')!
	archive_test_finish(mut app)
	assert app.status_key == 'archive.source_changed' && !os.exists(output)
	archive_set_field(mut app.archive_input, root)
	assert !app.browse_archive() && app.status_key == 'archive.not_regular'
	large := join_path(root, 'huge.tar')
	fd := C.open(&char(large.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
	assert fd >= 0 && C.ftruncate(fd, archive_max_bytes + 1) == 0 && desktop_close(fd) == 0
	archive_set_field(mut app.archive_input, large)
	assert !app.browse_archive() && app.status_key == 'archive.source_limit'
	archive_set_field(mut app.source_input, large)
	assert !app.create_archive() && app.status_key == 'archive.source_limit'
	archive_test_write(source, 'file', 'capture')
	archive_set_field(mut app.archive_input, source)
	assert app.browse_archive()
	assert app.poll()
	app.snapshot_mtime_nsec = if app.snapshot_mtime_nsec == 0 { i64(1) } else { i64(0) }
	archive_test_finish(mut app)
	assert app.status_key == 'archive.source_unstable' && app.loaded_path.len == 0

	assert !archive_absolute_valid('relative/path')
	assert !archive_absolute_valid('/safe/../escape')
	assert !archive_absolute_valid('/safe//file')
	assert !archive_absolute_valid('/safe/invalid\xff')
	assert archive_absolute_valid('/safe/日本語.txt')
}

fn test_archive_ustar_prefix_names_unicode_fields_paging_and_native_actions() {
	prefix := 'p'.repeat(130)
	name := '${prefix}/日本語.txt'
	defer {
		unsafe {
			prefix.free()
			name.free()
		}
	}
	data := archive_test_single(name, 'ok', `0`)
	defer { unsafe { data.free() } }
	mut entries := []ArchiveEntry{}
	defer {
		archive_free_entries(mut entries)
		unsafe { entries.free() }
	}
	total, status := archive_parse_tar(data, mut entries)
	assert status == '' && total == 2 && entries[0].name == name
	mut app := new_archive_app()
	defer { app.close_app() }
	app.focus_field(2)
	app.key_input('/日本語.txt')
	assert editor_bytes_text(app.source_input) == '/日本語.txt'
	app.key_input('\x01')
	app.paste_input('/safe/😀.txt\n\x1b')
	assert editor_bytes_text(app.source_input) == '/safe/😀.txt'
	app.key_input('\x7f')
	assert editor_bytes_text(app.source_input) == '/safe/😀.tx'
	app.key_input('\t')
	assert app.focus == 3
	app.key_input('\x1b[999~')
	assert app.output_input.len == 0
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 800, 680))!
	for action in ['archive.path', 'archive.destination', 'archive.source', 'archive.output',
		'archive.browse', 'archive.extract', 'archive.create', 'archive.cancel', 'archive.up',
		'archive.down'] {
		assert archive_test_action(tree, action)
	}
	free_tree(tree)
	app.key_input('\x1b[6~')
	assert app.scroll == 0
	app.close_app()
	app.close_app()
	assert app.entries.len == 0 && app.read_fd == -1
}

fn test_archive_checks_nanosecond_source_identity_entry_and_depth_limits() {
	root := archive_test_root('identity')
	defer { os.rmdir_all(root) or {} }
	source := join_path(root, 'source.txt')
	os.write_file(source, 'same size')!
	fd := archive_open_source(source)
	assert fd >= 0
	defer { desktop_close(fd) }
	mut info := C.stat{}
	assert unsafe { C.fstat(fd, &info) } == 0
	mut budget := ArchiveBudget{}
	mut entries := []ArchiveEntry{}
	defer {
		archive_free_entries(mut entries)
		unsafe { entries.free() }
	}
	assert archive_collect_entry(mut entries, 'source.txt', '', info, mut budget) == ''
	assert archive_source_matches(fd, entries[0])
	// Same seconds, inode and length with a different nanosecond stamp must fail.
	entries[0].mtime_nsec = if entries[0].mtime_nsec == 0 { i64(1) } else { i64(0) }
	assert !archive_source_matches(fd, entries[0])
	deep := 'a/'.repeat(32) + 'file'
	assert !archive_name_valid(deep)
	unsafe { deep.free() }
	long := 'a'.repeat(101)
	_, root_name_fits := archive_tar_name_parts(long)
	assert !root_name_fits
	unsafe { long.free() }
	mut bytes := []u8{cap: 512 * (archive_max_entries + 1) + 1024}
	for index in 0 .. archive_max_entries + 1 {
		number := index.str()
		name := 'file-${number}'
		header := archive_tar_header(ArchiveEntry{ name: name })
		for byte in header { bytes << byte }
		unsafe {
			number.free()
			name.free()
		}
	}
	for _ in 0 .. 1024 { bytes << u8(0) }
	_, status := archive_parse_tar(bytes, mut entries)
	assert status == 'archive.entry_limit'
	unsafe { bytes.free() }
	fifo := join_path(root, 'pipe.tar')
	assert C.mkfifo(&char(fifo.str), 0o600) == 0
	mut app := new_archive_app()
	defer { app.close_app() }
	archive_set_field(mut app.archive_input, fifo)
	assert !app.browse_archive() && app.status_key == 'archive.not_regular'
	archive_set_field(mut app.source_input, fifo)
	archive_set_field(mut app.output_input, join_path(root, 'unsafe.tar'))
	assert !app.create_archive() && app.status_key == 'archive.unsafe_entry'
	assert !os.exists(join_path(root, 'unsafe.tar'))
}
