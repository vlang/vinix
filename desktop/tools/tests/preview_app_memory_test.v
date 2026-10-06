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

const preview_heap_orientation_jpeg = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAADAAIDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABoQAAIDAQEAAAAAAAAAAAAAAAQFAgMHBgH/xAAVAQEBAAAAAAAAAAAAAAAAAAAHCv/EABsRAAIDAQEBAAAAAAAAAAAAAAUGAwQHCAkC/9oADAMBAAIRAxEAPwBUcDgqTYViycPlOCuEVZNnK0W5rnnDPmlo4PHphaLGTx5zzF05PnVVGRjVwwOaMSPbDGBhRd1183LXvKXgts1nUGkpiJGqTZdEdWAjVWtk3hLXK18yykyNuAAnJ2nAlFTCQ2LMkYpaVgYZcBUPmAWDFDhlWrUhlx9FupNZRvQbutKCwZDdDJ/ZHTqsJuOHOPOuhttsYv7a7iaFlpf3/K2Z7eGOerUilNuDqyMDazE/u0aZDZUzduX7H//Z'

fn preview_heap_exif_fixture(image []u8, orientation int, little bool) []u8 {
	mut bytes := []u8{len: image.len + 36}
	bytes[0] = 0xff
	bytes[1] = 0xd8
	bytes[2] = 0xff
	bytes[3] = 0xe1
	bytes[5] = 34
	bytes[6] = `E`
	bytes[7] = `x`
	bytes[8] = `i`
	bytes[9] = `f`
	bytes[12] = if little { `I` } else { `M` }
	bytes[13] = bytes[12]
	if little {
		bytes[14] = 42
		bytes[16] = 8
		bytes[20] = 1
		bytes[22] = 0x12
		bytes[23] = 1
		bytes[24] = 3
		bytes[26] = 1
		bytes[30] = u8(orientation)
	} else {
		bytes[15] = 42
		bytes[19] = 8
		bytes[21] = 1
		bytes[22] = 1
		bytes[23] = 0x12
		bytes[25] = 3
		bytes[29] = 1
		bytes[31] = u8(orientation)
	}
	for index in 2 .. image.len { bytes[index + 36] = image[index] }
	return bytes
}

fn test_preview_exif_parsing_repeated_valid_invalid_and_truncated_metadata_allocates_nothing() {
	image := base64.decode(preview_heap_orientation_jpeg)
	defer { unsafe { image.free() } }
	for little in [false, true]! {
		mut bytes := preview_heap_exif_fixture(image, 8, little)
		defer { unsafe { bytes.free() } }
		C.vinix_heap_begin()
		for index in 0 .. 10000 {
			assert preview_jpeg_orientation(bytes) == 8
			bytes[12] = `X`
			assert preview_jpeg_orientation(bytes) == 1
			bytes[12] = if little { `I` } else { `M` }
			assert preview_tiff_orientation(bytes, 12, 12 + index % 26) == 1
		}
		assert C.vinix_heap_end() == 0
	}
}

fn test_preview_repeated_oriented_jpeg_init_rotate_frame_export_close_releases_memory() {
	root := os.join_path(os.temp_dir(), 'vinix-preview-exif-heap-${os.getpid()}')
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	output := files_child_path(root, 'output.png')
	copy_path := files_child_path(root, 'original.jpg')
	defer { unsafe { output.free(); copy_path.free() } }
	image := base64.decode(preview_heap_orientation_jpeg)
	mut paths := []string{cap: 16}
	unsafe { paths.flags |= .noslices }
	for little in [false, true]! {
		for orientation in 1 .. 9 {
			name := paths.len.str()
			path := files_child_path(root, name)
			unsafe { name.free() }
			paths << path
			bytes := preview_heap_exif_fixture(image, orientation, little)
			os.write_file_array(path, bytes)!
			unsafe { bytes.free() }
		}
	}
	unsafe { image.free() }
	defer {
		// V3 Array_string.free releases each transferred path as well as the
		// array buffer; freeing the elements separately would double-free them.
		unsafe { paths.free() }
	}
	mut warm := PreviewApp{}
	preview_set_field(mut warm.open_path, paths[0])
	assert warm.open_image()
	begin_frame_elements()
	free_tree(warm.build(ui2.rect(0, 0, 420, 220))!)
	warm.close_app()
	C.vinix_heap_begin()
	for cycle in 0 .. 100 {
		mut app := PreviewApp{}
		preview_set_field(mut app.open_path, paths[cycle % paths.len])
		assert app.open_image()
		assert app.orientation == cycle % 8 + 1 && app.width == 2 && app.height == 3
		for _ in 0 .. 4 {
			app.rotate(1)
			app.set_viewport(2, 2)
			app.set_zoom(400)
			app.pan(10, 10)
			assert app.publish_surface()
			preview_set_field(mut app.export_path, output)
			assert app.export_image(false)
			assert desktop_unlink(output) == 0
		}
		app.fit_image()
		begin_frame_elements()
		free_tree(app.build(ui2.rect(0, 0, 420, 220))!)
		preview_set_field(mut app.export_path, copy_path)
		assert app.export_image(true)
		assert desktop_unlink(copy_path) == 0
		app.close_app()
		app.close_app()
	}
	assert C.vinix_heap_end() == 0
}

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
