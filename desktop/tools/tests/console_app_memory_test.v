// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_console_refresh_filter_export_and_frames_release_owned_allocations() {
	home := os.join_path(os.temp_dir(), 'vinix-console-heap-${os.getpid()}')
	os.mkdir(home)!
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
	os.write_file(path, 'INFO ready\nERROR 日本語\nERROR 😀\n')!
	mut app := new_console_app(path, export_path)
	begin_frame_elements()
	warm := app.build(ui2.rect(0, 0, 800, 560))!
	free_tree(warm)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert !app.refresh()
		app.focus_field(1)
		app.key_input('\x01')
		app.paste_input('ERROR')
		app.export_visible()
		assert app.export_status == 'console.export_saved'
		assert desktop_unlink(export_path) == 0
		app.key_input('\x01日本語\x7f')
		begin_frame_elements()
		tree := app.build(ui2.rect(0, 0, 800, 560))!
		free_tree(tree)
	}
	app.close_app()
	assert C.vinix_heap_end() == 0
}

fn test_console_dense_rows_and_sanitization_release_growth_buffers_on_close() {
	home := os.join_path(os.temp_dir(), 'vinix-console-growth-${os.getpid()}')
	os.mkdir(home)!
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
	dense := '日本語\n'.repeat(10000)
	defer { unsafe { dense.free() } }
	os.write_file(path, dense)!
	C.vinix_heap_begin()
	mut app := new_console_app(path, export_path)
	assert app.lines.len == 10000
	assert app.matching.len == 10000
	for _ in 0 .. 20 {
		clean := console_sanitize('😀\xff\x1b\r\n日\xc2\x85')
		unsafe { clean.free() }
		empty := console_sanitize('')
		unsafe { empty.free() }
		app.refilter()
		data := app.visible_text()
		assert data == dense
		unsafe { data.free() }
	}
	app.close_app()
	app.close_app()
	assert C.vinix_heap_end() == 0
}
