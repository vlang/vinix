// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn C.mkfifo(path &char, mode u32) int

fn console_test_directory(name string) string {
	path := os.join_path(os.temp_dir(), 'vinix-console-${os.getpid()}-${name}')
	os.mkdir(path) or { panic(err) }
	return path
}

fn test_console_reads_real_log_filters_exactly_and_exports_without_overwrite() {
	home := console_test_directory('filter')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := join_path(home, 'source.log')
	export_path := join_path(home, 'export.txt')
	defer {
		unsafe {
			path.free()
			export_path.free()
		}
	}
	os.write_file(path, 'INFO ready\nERROR literal [a].*\nerror lowercase\nERROR 日本語\n')!
	mut app := new_console_app(path, export_path)
	defer { app.close_app() }
	assert app.status_key == ''
	assert app.lines.len == 4
	app.handle('console.filter')!
	app.paste_input('ERROR')
	assert app.matching.len == 2
	assert app.count_text == '2 / 4'
	report := app.visible_text()
	defer { unsafe { report.free() } }
	assert report == 'ERROR literal [a].*\nERROR 日本語\n'
	app.handle('console.export')!
	assert app.export_status == 'console.export_saved'
	saved := os.read_file(export_path)!
	defer { unsafe { saved.free() } }
	assert saved == report
	app.handle('console.export')!
	assert app.export_status == 'console.export_exists'
	app.key_input('\x01[a].*')
	assert app.matching.len == 1
	app.key_input('\x01missing')
	assert app.matching.len == 0
	app.key_input('\x01\x7f')
	assert app.matching.len == 4
}

fn test_console_rejects_devices_links_directories_and_fifo_without_blocking() {
	home := console_test_directory('special')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	missing := join_path(home, 'missing.log')
	fifo := join_path(home, 'pipe')
	link := join_path(home, 'link')
	regular := join_path(home, 'regular.log')
	defer {
		unsafe {
			missing.free()
			fifo.free()
			link.free()
			regular.free()
		}
	}
	assert C.mkfifo(&char(fifo.str), 0o600) == 0
	os.write_file(regular, 'real\n')!
	os.symlink(regular, link)!
	for path in [fifo, link, home, '/dev/null']! {
		result := console_read_snapshot(path)
		assert result.status == 'console.not_regular'
		assert result.text == ''
	}
	assert console_read_snapshot(missing).status == 'console.no_file'
	assert console_read_snapshot('relative.log').status == 'console.invalid_path'
	assert console_read_snapshot('/tmp/bad\npath').status == 'console.invalid_path'
	assert console_write_export(fifo, 'test') == 'console.export_exists'
	assert console_write_export(link, 'test') == 'console.export_exists'
}

fn test_console_shortened_export_path_does_not_use_old_buffer_suffix() {
	home := console_test_directory('short-export')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := join_path(home, 'source.log')
	long_path := join_path(home, 'export-with-a-long-name.txt')
	short_path := join_path(home, 'x')
	defer {
		unsafe {
			path.free()
			long_path.free()
			short_path.free()
		}
	}
	os.write_file(path, 'real rows\n')!
	mut app := new_console_app(path, long_path)
	defer { app.close_app() }
	app.handle('console.export_path')!
	app.key_input('\x01')
	app.paste_input(short_path)
	assert editor_bytes_text(app.export_input) == short_path
	// A stale non-NUL byte really remains beyond the shortened field.
	assert unsafe { (&u8(app.export_input.data))[app.export_input.len] } != 0
	app.export_visible()
	assert app.export_status == 'console.export_saved'
	assert os.exists(short_path)
	assert !os.exists(long_path)
	data := os.read_file(short_path)!
	defer { unsafe { data.free() } }
	assert data == 'real rows\n'
}

fn test_console_tail_bound_rotation_truncation_and_missing_file_clear_old_rows() {
	home := console_test_directory('tail')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := join_path(home, 'source.log')
	rotated := join_path(home, 'source.log.old')
	defer {
		unsafe {
			path.free()
			rotated.free()
		}
	}
	long_line := 'x'.repeat(console_tail_bytes + 30)
	large := 'old\n${long_line}\nlast 日本語\n'
	defer {
		unsafe {
			long_line.free()
			large.free()
		}
	}
	os.write_file(path, large)!
	mut app := new_console_app(path, rotated)
	defer { app.close_app() }
	assert app.limited
	assert app.text.len <= console_tail_bytes
	assert app.text == 'last 日本語\n'
	os.write_file(path, '${long_line}\n')!
	assert app.refresh()
	assert app.limited && app.lines.len == 1
	assert app.text.len == console_tail_bytes
	os.write_file(path, 'short\n')!
	assert app.refresh()
	assert !app.limited
	assert app.text == 'short\n'
	os.rename(path, rotated)!
	os.write_file(path, 'new inode\n')!
	assert app.refresh()
	assert app.text == 'new inode\n'
	os.rm(path)!
	assert app.refresh()
	assert app.status_key == 'console.no_file'
	assert app.text == '' && app.lines.len == 0 && app.matching.len == 0
	app.export_visible()
	assert app.export_status == ''
}

fn test_console_sanitizes_utf8_controls_and_line_endings_without_expanding_tail() {
	input := 'ASCII\r\n日本語 😀\tend\rnext\x1b[31m\x00\x7f\xc2\x85\xff\xed\xa0\x80'
	clean := console_sanitize(input)
	defer { unsafe { clean.free() } }
	assert clean == 'ASCII\n日本語 😀 end\nnext?[31m???????'
	assert clean.len <= input.len
	assert clean.index_u8(0x1b) == -1
	assert console_sanitize('') == ''
}

fn test_console_poll_is_throttled_and_scroll_pauses_tail_following() {
	home := console_test_directory('poll')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := join_path(home, 'source.log')
	export_path := join_path(home, 'export.txt')
	defer {
		unsafe {
			path.free()
			export_path.free()
		}
	}
	os.write_file(path, '1\n2\n3\n4\n5\n6\n')!
	mut app := new_console_app(path, export_path)
	defer { app.close_app() }
	app.page_rows = 2
	app.refilter()
	assert app.scroll == 4
	app.last_poll_ms = 100
	os.write_file(path, 'changed\n')!
	assert !app.poll_at(1099)
	assert app.text == '1\n2\n3\n4\n5\n6\n'
	assert app.poll_at(1100)
	assert app.text == 'changed\n'
	assert !app.poll_at(2100)
	assert app.last_poll_ms == 2100
	os.write_file(path, '1\n2\n3\n4\n5\n6\n')!
	app.refresh()
	app.key_input('\x1b[H')
	assert !app.follow && app.scroll == 0
	app.key_input('\x1b[6~')
	assert app.scroll == 2
	assert !app.poll_at(10000)
	app.handle('console.follow')!
	assert app.follow && app.scroll == 4
}

fn test_console_fields_keep_utf8_and_paste_cannot_trigger_commands() {
	home := console_test_directory('input')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := join_path(home, 'source.log')
	export_path := join_path(home, 'export.txt')
	defer {
		unsafe {
			path.free()
			export_path.free()
		}
	}
	os.write_file(path, '日本語 😀\n')!
	mut app := new_console_app(path, export_path)
	defer { app.close_app() }
	app.handle('console.filter')!
	app.key_input('\xe6\x97')
	app.key_input('\xa5')
	assert editor_bytes_text(app.filter_input) == '日'
	app.key_input('本語 😀')
	assert app.matching.len == 1
	app.key_input('\x7f')
	assert editor_bytes_text(app.filter_input) == '日本語 '
	app.key_input('\x01')
	app.paste_input('日本語\n\t\x1b\x01\x7f\xff')
	assert app.focus == 1
	assert editor_bytes_text(app.filter_input) == '日本語'
	assert app.matching.len == 1
	assert !os.exists(export_path)
	app.key_input('\x01')
	full := '日'.repeat(100)
	defer { unsafe { full.free() } }
	app.paste_input(full)
	assert app.filter_input.len == 255
	assert app.filter_input[254] == 0xa5
	app.key_input('\x1b')
	app.paste_input('ignored')
	assert app.filter_input.len == 255
}

fn test_console_jump_open_empty_file_horizontal_view_and_build() {
	home := console_test_directory('jump')
	defer {
		os.rmdir_all(home) or {}
		unsafe { home.free() }
	}
	path := join_path(home, 'source.log')
	export_path := join_path(home, 'export.txt')
	defer {
		unsafe {
			path.free()
			export_path.free()
		}
	}
	os.write_file(path, '')!
	mut app := new_console_app('/missing-console-fixture', export_path)
	defer { app.close_app() }
	open_event := jump_open_prefix + path
	defer { unsafe { open_event.free() } }
	app.handle(open_event)!
	assert app.path == path && editor_bytes_text(app.path_input) == path
	assert app.status_key == '' && app.lines.len == 0
	os.write_file(path, '日😀abc\n')!
	app.refresh()
	assert console_line_window(app.text, app.lines[0], 1, 2) == '😀a'
	assert console_line_window(app.text, app.lines[0], 100, 2) == ''
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 800, 560))!
	free_tree(tree)
	assert app.page_rows > 1
	oversized := '/'.repeat(console_field_limit + 1)
	bad_event := jump_open_prefix + oversized
	defer {
		unsafe {
			oversized.free()
			bad_event.free()
		}
	}
	app.handle(bad_event)!
	assert app.path == path && editor_bytes_text(app.path_input) == path
	assert app.status_key == 'console.invalid_path'
	assert app.path_input.len <= console_field_limit
	app.set_source('/tmp/control\npath')
	assert app.path == path
	mut invalid := new_console_app(oversized, oversized)
	defer { invalid.close_app() }
	assert invalid.path == '' && invalid.path_input.len == 0 && invalid.export_input.len == 0
	assert invalid.status_key == 'console.invalid_path'
}
