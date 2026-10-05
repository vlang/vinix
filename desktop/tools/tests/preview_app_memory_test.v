// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.base64
import os
import ui2

#include "@VMODROOT/heap_tracker.h"

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32
fn C.vinix_heap_size_at(u32) u64

fn test_preview_repeated_open_rotate_pan_export_and_frames_release_owned_memory() {
	root := os.join_path(os.temp_dir(), 'vinix-preview-heap-${os.getpid()}')
	os.mkdir(root)!
	defer {
		os.rmdir_all(root) or {}
		unsafe { root.free() }
	}
	path := join_path(root, 'source.png')
	broken_path := join_path(root, 'broken.png')
	export_path := join_path(root, 'output.png')
	defer {
		unsafe {
			path.free()
			broken_path.free()
			export_path.free()
		}
	}
	image := base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAD0lEQVR4nGP4z8DwHwgbABB5A359Y87XAAAAAElFTkSuQmCC')
	os.write_file_array(path, image)!
	broken := [u8(0x89), `P`, `N`, `G`, `\r`, `\n`, 0x1a, `\n`]
	os.write_file_array(broken_path, broken)!
	unsafe { broken.free() }
	unsafe { image.free() }
	mut app := PreviewApp{}
	preview_set_field(mut app.open_path, path)
	assert app.open_image()
	begin_frame_elements()
	free_tree(app.build(ui2.rect(0, 0, 760, 420))!)
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		assert app.open_image()
		preview_set_field(mut app.open_path, broken_path)
		assert !app.open_image() && app.pixels != unsafe { nil }
		preview_set_field(mut app.open_path, path)
		app.rotate(1)
		app.rotate(-1)
		app.set_zoom(400)
		app.pan(10, 10)
		app.fit_image()
		app.focus_field(.export_path)
		app.paste_input(export_path)
		assert app.export_image(false)
		assert desktop_unlink(export_path) == 0
		assert app.export_image(true)
		assert desktop_unlink(export_path) == 0
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 760, 420))!)
		app.focus_field(.open_path)
		app.key_input('\x01')
		app.paste_input(path)
	}
	app.close_app()
	app.close_app()
	live := C.vinix_heap_end()
	if live != 0 {
		count := C.vinix_heap_count()
		for index in 0 .. if count < 10 { count } else { 10 } {
			eprintln('Preview retained allocation: ${C.vinix_heap_size_at(index)} bytes')
		}
	}
	assert live == 0, 'Preview retained ${live} bytes after closing'
}

fn test_preview_path_growth_utf8_and_decode_errors_release_owned_memory() {
	short := '日本😀'
	long := '日'.repeat(340)
	defer { unsafe { long.free() } }
	C.vinix_heap_begin()
	mut app := PreviewApp{}
	for _ in 0 .. 100 {
		app.focus_field(.open_path)
		app.paste_input(long)
		app.key_input('\x7f\x7f\x7f')
		app.key_input('\x01')
		app.paste_input(short)
		assert !app.open_image()
		app.focus_field(.export_path)
		app.paste_input(long)
		app.key_input('\x01')
		app.key_input('\xe6\x97')
		app.key_input('\xa5')
		app.key_input('\x7f')
		assert !app.export_image(false)
	}
	app.close_app()
	assert C.vinix_heap_end() == 0
}
