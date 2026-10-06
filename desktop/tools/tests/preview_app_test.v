// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.base64
import os
import ui2

fn C.mkfifo(&char, u32) int

const preview_test_png = 'iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAD0lEQVR4nGP4z8DwHwgbABB5A359Y87XAAAAAElFTkSuQmCC'
// Six distinct pixels in an asymmetric 2x3 JPEG (quality 100, no subsampling).
const preview_test_orientation_jpeg = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/wAARCAADAAIDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABoQAAIDAQEAAAAAAAAAAAAAAAQFAgMHBgH/xAAVAQEBAAAAAAAAAAAAAAAAAAAHCv/EABsRAAIDAQEBAAAAAAAAAAAAAAUGAwQHCAkC/9oADAMBAAIRAxEAPwBUcDgqTYViycPlOCuEVZNnK0W5rnnDPmlo4PHphaLGTx5zzF05PnVVGRjVwwOaMSPbDGBhRd1183LXvKXgts1nUGkpiJGqTZdEdWAjVWtk3hLXK18yykyNuAAnJ2nAlFTCQ2LMkYpaVgYZcBUPmAWDFDhlWrUhlx9FupNZRvQbutKCwZDdDJ/ZHTqsJuOHOPOuhttsYv7a7iaFlpf3/K2Z7eGOerUilNuDqyMDazE/u0aZDZUzduX7H//Z'

fn preview_test_put_tiff(mut bytes []u8, at int, value u32, size int, little bool) {
	for index in 0 .. size {
		shift := if little { index * 8 } else { (size - 1 - index) * 8 }
		bytes[at + index] = u8(value >> shift)
	}
}

fn preview_test_exif_segment(orientation int, little bool) []u8 {
	mut segment := []u8{len: 36}
	segment[0] = 0xff
	segment[1] = 0xe1
	segment[3] = 34
	segment[4] = `E`
	segment[5] = `x`
	segment[6] = `i`
	segment[7] = `f`
	segment[10] = if little { `I` } else { `M` }
	segment[11] = segment[10]
	preview_test_put_tiff(mut segment, 12, 42, 2, little)
	preview_test_put_tiff(mut segment, 14, 8, 4, little)
	preview_test_put_tiff(mut segment, 18, 1, 2, little)
	preview_test_put_tiff(mut segment, 20, 0x0112, 2, little)
	preview_test_put_tiff(mut segment, 22, 3, 2, little)
	preview_test_put_tiff(mut segment, 24, 1, 4, little)
	preview_test_put_tiff(mut segment, 28, u32(orientation), 2, little)
	return segment
}

fn preview_test_add_segment(image []u8, segment []u8) []u8 {
	mut result := []u8{len: image.len + segment.len}
	result[0] = 0xff
	result[1] = 0xd8
	for index, byte in segment { result[2 + index] = byte }
	for index in 2 .. image.len { result[index + segment.len] = image[index] }
	return result
}

fn test_preview_exif_parser_accepts_both_byte_orders_and_bounds_malformed_records() {
	image := base64.decode(preview_test_orientation_jpeg)
	defer { unsafe { image.free() } }
	assert preview_jpeg_orientation(image) == 1
	for little in [false, true]! {
		for orientation in 1 .. 9 {
			segment := preview_test_exif_segment(orientation, little)
			jpeg := preview_test_add_segment(image, segment)
			assert preview_jpeg_orientation(jpeg) == orientation
			unsafe { jpeg.free(); segment.free() }
		}
		for change in 0 .. 12 {
			mut segment := preview_test_exif_segment(6, little)
			match change {
				0 { segment[10] = `X` }
				1 { preview_test_put_tiff(mut segment, 12, 43, 2, little) }
				2 { preview_test_put_tiff(mut segment, 14, 0xfffffff0, 4, little) }
				3 { preview_test_put_tiff(mut segment, 14, 7, 4, little) }
				4 { preview_test_put_tiff(mut segment, 14, 9, 4, little) }
				5 { preview_test_put_tiff(mut segment, 18, 65535, 2, little) }
				6 { preview_test_put_tiff(mut segment, 22, 4, 2, little) }
				7 { preview_test_put_tiff(mut segment, 24, 2, 4, little) }
				8 { preview_test_put_tiff(mut segment, 28, 0, 2, little) }
				9 { preview_test_put_tiff(mut segment, 28, 9, 2, little) }
				10 { segment[3] = 33 }
				else { segment[3] = 1 }
			}
			jpeg := preview_test_add_segment(image, segment)
			assert preview_jpeg_orientation(jpeg) == 1
			unsafe { jpeg.free(); segment.free() }
		}
		segment := preview_test_exif_segment(8, little)
		for length in 0 .. segment.len {
			mut truncated := []u8{len: length + 2}
			truncated[0] = 0xff
			truncated[1] = 0xd8
			for index in 0 .. length { truncated[index + 2] = segment[index] }
			assert preview_jpeg_orientation(truncated) == 1
			unsafe { truncated.free() }
		}
		mut directory := []u8{len: segment.len + 12}
		for index, byte in segment { directory[index] = byte }
		directory[3] = u8(directory.len - 2)
		preview_test_put_tiff(mut directory, 18, 2, 2, little)
		for index in 0 .. 12 { directory[32 + index] = segment[20 + index] }
		duplicate := preview_test_add_segment(image, directory)
		assert preview_jpeg_orientation(duplicate) == 1
		unsafe { duplicate.free() }
		preview_test_put_tiff(mut directory, 20, 0x0100, 2, little)
		// Unknown tags and even a cyclic thumbnail offset are never followed.
		preview_test_put_tiff(mut directory, 44, 8, 4, little)
		with_unknown := preview_test_add_segment(image, directory)
		assert preview_jpeg_orientation(with_unknown) == 8
		unsafe { with_unknown.free(); directory.free(); segment.free() }
		mut padded := []u8{len: 40}
		original := preview_test_exif_segment(5, little)
		for index in 0 .. 18 { padded[index] = original[index] }
		for index in 18 .. original.len { padded[index + 4] = original[index] }
		padded[3] = 38
		preview_test_put_tiff(mut padded, 14, 12, 4, little)
		shifted_ifd := preview_test_add_segment(image, padded)
		assert preview_jpeg_orientation(shifted_ifd) == 5
		preview_test_put_tiff(mut padded, 22, 0, 2, little)
		empty_ifd := preview_test_add_segment(image, padded)
		assert preview_jpeg_orientation(empty_ifd) == 1
		unsafe { empty_ifd.free(); shifted_ifd.free(); padded.free(); original.free() }
	}
	assert preview_tiff_orientation(image, -1, image.len) == 1
	assert preview_tiff_orientation(image, 0, image.len + 1) == 1
	assert preview_tiff_orientation(image, 10, 9) == 1
}

fn test_preview_exif_scanner_skips_other_metadata_and_stops_before_jpeg_scan() {
	image := base64.decode(preview_test_orientation_jpeg)
	segment := preview_test_exif_segment(6, false)
	jpeg := preview_test_add_segment(image, segment)
	defer { unsafe { image.free(); segment.free(); jpeg.free() } }
	other := [u8(0xff), 0xe1, 0, 8, `X`, `M`, `P`, 0, 0, 0, 0xff, 0x01, 0xff, 0xd0, 0xff]
	preceded := preview_test_add_segment(jpeg, other)
	assert preview_jpeg_orientation(preceded) == 6
	unsafe { preceded.free(); other.free() }
	scan := [u8(0xff), 0xda, 0, 2]
	after_scan := preview_test_add_segment(jpeg, scan)
	assert preview_jpeg_orientation(after_scan) == 1
	unsafe { after_scan.free(); scan.free() }
	mut first_bad := preview_test_exif_segment(9, true)
	conflicting := preview_test_add_segment(jpeg, first_bad)
	assert preview_jpeg_orientation(conflicting) == 1
	unsafe { conflicting.free(); first_bad.free() }
	mut many := []u8{len: preview_max_jpeg_metadata_segments * 4}
	for index in 0 .. preview_max_jpeg_metadata_segments {
		many[index * 4] = 0xff
		many[index * 4 + 1] = 0xe0
		many[index * 4 + 3] = 2
	}
	bounded := preview_test_add_segment(jpeg, many)
	assert preview_jpeg_orientation(bounded) == 1
	unsafe { bounded.free(); many.free() }
}

fn test_preview_all_exif_orientations_compose_with_each_user_rotation() {
	expected := [[0, 4, 8, 12, 16, 20]!, [4, 0, 12, 8, 20, 16]!,
		[20, 16, 12, 8, 4, 0]!, [16, 20, 8, 12, 0, 4]!, [0, 8, 16, 4, 12, 20]!,
		[16, 8, 0, 20, 12, 4]!, [20, 12, 4, 16, 8, 0]!, [4, 12, 20, 0, 8, 16]!]!
	for orientation in 1 .. 9 {
		base_width := if orientation >= 5 { 3 } else { 2 }
		base_height := if orientation >= 5 { 2 } else { 3 }
		mut app := PreviewApp{width: 2, height: 3, orientation: orientation}
		for rotation in 0 .. 4 {
			app.rotation = rotation
			width, height := app.oriented_dimensions()
			assert width == if rotation & 1 == 0 { base_width } else { base_height }
			assert height == if rotation & 1 == 0 { base_height } else { base_width }
			for y in 0 .. height {
				for x in 0 .. width {
					index := match rotation {
						1 { (base_height - 1 - x) * base_width + y }
						2 { (base_height - 1 - y) * base_width + base_width - 1 - x }
						3 { x * base_width + base_width - 1 - y }
						else { y * base_width + x }
					}
					assert app.pixel_offset(x, y) == expected[orientation - 1][index]
				}
			}
		}
	}
}

fn test_preview_oriented_jpeg_surface_fit_pan_png_and_exact_original_copy() {
	root := preview_test_root('orientation')
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := files_child_path(root, 'image.jpg')
	export_path := files_child_path(root, 'oriented.png')
	copy_path := files_child_path(root, 'original.jpg')
	defer { unsafe { path.free(); export_path.free(); copy_path.free() } }
	image := base64.decode(preview_test_orientation_jpeg)
	defer { unsafe { image.free() } }
	mut app := PreviewApp{}
	defer { app.close_app() }
	for little in [false, true]! {
		for orientation in 1 .. 9 {
			segment := preview_test_exif_segment(orientation, little)
			jpeg := preview_test_add_segment(image, segment)
			os.write_file_array(path, jpeg)!
			preview_set_field(mut app.open_path, path)
			assert app.open_image()
			assert app.width == 2 && app.height == 3 && app.orientation == orientation
			for rotation in 0 .. 4 {
				width, height := app.oriented_dimensions()
				app.set_viewport(width, height)
				app.set_zoom(100)
				assert app.publish_surface()
				surface := open_vinix_surface(app.surface_path) or { panic('Missing oriented surface') }
				for y in 0 .. height {
					for x in 0 .. width {
						at := app.pixel_offset(x, y)
						rgb := unsafe { u32(app.pixels[at]) << 16 | u32(app.pixels[at + 1]) << 8
							| u32(app.pixels[at + 2]) }
						assert surface.pixel(x, y) == rgb
					}
				}
				surface.close()
				preview_set_field(mut app.export_path, export_path)
				assert app.export_image(false)
				mut reopened := PreviewApp{}
				preview_set_field(mut reopened.open_path, export_path)
				assert reopened.open_image()
				assert reopened.width == width && reopened.height == height && reopened.orientation == 1
				for y in 0 .. height {
					for x in 0 .. width {
						for channel in 0 .. 4 {
							assert unsafe { reopened.pixels[(y * width + x) * 4 + channel] }
								== unsafe { app.pixels[app.pixel_offset(x, y) + channel] }
						}
					}
				}
				reopened.close_app()
				assert desktop_unlink(export_path) == 0
				app.rotate(1)
			}
			assert app.rotation == 0 && app.width == 2 && app.height == 3
			app.set_viewport(1, 1)
			app.set_zoom(400)
			width, height := app.oriented_dimensions()
			app.pan(9999, 9999)
			assert app.pan_x == width * 4 - 1 && app.pan_y == height * 4 - 1
			app.fit_image()
			geometry := app.geometry()
			assert geometry.width == 1 && geometry.height == 1
			// Manual turns never alter the source metadata or decoded dimensions.
			app.rotate(1)
			os.write_file(path, 'changed after open')!
			preview_set_field(mut app.export_path, copy_path)
			assert app.export_image(true)
			copy := os.read_bytes(copy_path)!
			assert copy == jpeg
			unsafe { copy.free() }
			assert desktop_unlink(copy_path) == 0
			old_pixels := app.pixels
			preview_set_field(mut app.open_path, path)
			assert !app.open_image() && app.pixels == old_pixels && app.orientation == orientation
			assert app.rotation == 1
			unsafe { jpeg.free(); segment.free() }
		}
	}
	// Invalid EXIF still decodes safely, replacing the previous orientation.
	mut segment := preview_test_exif_segment(6, true)
	segment[10] = `X`
	malformed := preview_test_add_segment(image, segment)
	os.write_file_array(path, malformed)!
	preview_set_field(mut app.open_path, path)
	assert app.open_image() && app.orientation == 1 && app.rotation == 0
	assert app.width == 2 && app.height == 3
	unsafe { malformed.free(); segment.free() }
}

fn preview_test_root(name string) string {
	root := os.join_path(os.temp_dir(), 'vinix-preview-${name}-${os.getpid()}')
	os.rmdir_all(root) or {}
	os.mkdir(root) or { panic(err) }
	return root
}

fn preview_test_fixture(path string) {
	bytes := base64.decode(preview_test_png)
	os.write_file_array(path, bytes) or { panic(err) }
	unsafe { bytes.free() }
}

fn preview_test_write_image(path string, width int, height int, pixels []u8) {
	// Borrow the test's pixel buffer for the writer; the application normally
	// owns a decoder allocation and close_app releases it through stb_image.
	app := PreviewApp{ width: width, height: height, pixels: pixels.data }
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
	assert fd >= 0
	assert app.write_png(fd)
	assert desktop_close(fd) == 0
}

fn preview_test_has_action(element ui2.Element, action string) bool {
	if element.id == action { return true }
	for child in element.children {
		if preview_test_has_action(child, action) { return true }
	}
	return false
}

fn test_preview_opens_png_and_rejected_paths_preserve_the_image() {
	root := preview_test_root('open')
	defer { os.rmdir_all(root) or {} }
	path := join_path(root, 'image.png')
	preview_test_fixture(path)
	mut app := PreviewApp{}
	defer { app.close_app() }
	preview_set_field(mut app.open_path, path)
	assert app.open_image()
	assert app.width == 2 && app.height == 1
	assert unsafe { app.pixels[0] } == 255
	assert unsafe { app.pixels[7] } == 128
	assert app.source.len > 0 && app.loaded_path == path
	assert app.export_path.len == 0
	old := app.pixels
	bad := join_path(root, 'unsupported.pdf')
	os.write_file(bad, '%PDF-1.7\n')!
	preview_set_field(mut app.open_path, bad)
	assert !app.open_image()
	assert app.status_key == 'preview.status.pdf_unavailable'
	assert app.pixels == old && app.loaded_path == path
	preview_set_field(mut app.open_path, root)
	assert !app.open_image() && app.pixels == old
	preview_set_field(mut app.open_path, '')
	assert !app.open_image() && app.status_key == 'preview.status.enter_path'
	assert app.pixels == old
	assert !preview_dimensions_valid(8193, 1)
	assert !preview_dimensions_valid(4096, 4096)
	assert preview_dimensions_valid(4096, 2048)
}

fn test_preview_rejects_fifo_large_sources_and_oversize_png_headers() {
	root := preview_test_root('limits')
	defer { os.rmdir_all(root) or {} }
	mut app := PreviewApp{}
	defer { app.close_app() }
	fifo := join_path(root, 'fifo')
	assert C.mkfifo(&char(fifo.str), 0o600) == 0
	preview_set_field(mut app.open_path, fifo)
	assert !app.open_image() && app.status_key == 'preview.status.cannot_open'
	large := join_path(root, 'large.png')
	fd := C.open(&char(large.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
	assert fd >= 0
	assert C.ftruncate(fd, preview_max_source + 1) == 0
	assert desktop_close(fd) == 0
	preview_set_field(mut app.open_path, large)
	assert !app.open_image() && app.status_key == 'preview.status.source_limit'
	wide := join_path(root, 'wide.png')
	mut png := base64.decode(preview_test_png)
	preview_put_be32(png.data, 16, 8193)
	os.write_file_array(wide, png)!
	unsafe { png.free() }
	preview_set_field(mut app.open_path, wide)
	assert !app.open_image() && app.status_key == 'preview.status.pixel_limit'
	assert app.pixels == unsafe { nil }
}

fn test_preview_rotation_png_alpha_and_original_copy_do_not_overwrite() {
	root := preview_test_root('export')
	defer { os.rmdir_all(root) or {} }
	path := join_path(root, 'source.png')
	pixels := [u8(255), 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 255, 255, 255, 0, 255, 255, 0, 255,
		64, 0, 255, 255, 0]
	preview_test_write_image(path, 2, 3, pixels)
	mut app := PreviewApp{}
	defer { app.close_app() }
	preview_set_field(mut app.open_path, path)
	assert app.open_image()
	original := app.source.clone()
	defer { unsafe { original.free() } }
	expected_offsets := [[0, 4, 8, 12, 16, 20]!, [16, 8, 0, 20, 12, 4]!, [20, 16, 12, 8, 4, 0]!,
		[4, 12, 20, 0, 8, 16]!]!
	for rotation in 0 .. 4 {
		app.rotation = rotation
		oriented_width, oriented_height := app.oriented_dimensions()
		for y in 0 .. oriented_height {
			for x in 0 .. oriented_width {
				assert app.pixel_offset(x, y) == expected_offsets[rotation][y * oriented_width + x]
			}
		}
	}
	app.rotation = 0
	app.rotate(1)
	width, height := app.oriented_dimensions()
	assert width == 3 && height == 2
	assert app.pixel_offset(0, 0) == 16
	assert app.pixel_offset(2, 1) == 4
	export_path := join_path(root, 'rotated.png')
	preview_set_field(mut app.export_path, export_path)
	assert app.export_image(false)
	mut reopened := PreviewApp{}
	defer { reopened.close_app() }
	preview_set_field(mut reopened.open_path, export_path)
	assert reopened.open_image()
	assert reopened.width == 3 && reopened.height == 2
	assert unsafe { reopened.pixels[0] } == 255
	assert unsafe { reopened.pixels[2] } == 255
	assert unsafe { reopened.pixels[3] } == 64
	assert unsafe { reopened.pixels[23] } == 128
	assert !app.export_image(false) && app.status_key == 'preview.status.exists'
	for _ in 0 .. 3 { app.rotate(1) }
	assert app.rotation == 0 && app.width == 2 && app.height == 3
	for index, byte in pixels {
		assert unsafe { app.pixels[index] } == byte
	}
	// Original Copy comes from the opened image, even if the source changes.
	os.write_file(path, 'replaced after Open')!
	copy_path := join_path(root, 'original.png')
	preview_set_field(mut app.export_path, copy_path)
	assert app.export_image(true)
	copy := os.read_bytes(copy_path)!
	assert copy == original
	unsafe { copy.free() }
	link := join_path(root, 'link.png')
	os.symlink(copy_path, link)!
	preview_set_field(mut app.export_path, link)
	assert !app.export_image(false) && app.status_key == 'preview.status.exists'
	assert os.read_bytes(copy_path)! == original
	preview_set_field(mut app.export_path, '')
	assert !app.export_image(false) && app.status_key == 'preview.status.export_path'
	failed := join_path(root, 'failed.png')
	preview_set_field(mut app.export_path, failed)
	app.width = 0
	assert !app.export_image(false) && !os.exists(failed)
}

fn test_preview_fit_zoom_pan_surfaces_actions_and_idempotent_close() {
	root := preview_test_root('surface')
	defer { os.rmdir_all(root) or {} }
	path := join_path(root, 'image.png')
	preview_test_fixture(path)
	mut app := PreviewApp{}
	preview_set_field(mut app.open_path, path)
	app.handle(jump_open_prefix + path)!
	assert app.pixels != unsafe { nil }
	oversized_jump := jump_open_prefix + 'x'.repeat(preview_max_path + 1)
	app.handle(oversized_jump)!
	assert app.loaded_path == path && editor_bytes_text(app.open_path) == path
	assert app.status_key == 'preview.status.cannot_open'
	app.handle(jump_open_prefix + path + '\x00ignored')!
	assert app.loaded_path == path && editor_bytes_text(app.open_path) == path
	app.set_viewport(2, 1)
	app.set_zoom(100)
	assert app.publish_surface()
	first := app.surface_path.clone()
	defer { unsafe { first.free() } }
	surface := open_vinix_surface(first) or { panic('Preview surface was not readable') }
	assert surface.width == 2 && surface.height == 1
	assert surface.pixel(0, 0) == 0xff0000
	assert surface.pixel(1, 0) == 0x7fff7f
	surface.close()
	app.set_viewport(1, 1)
	app.set_zoom(400)
	app.pan(10000, 10000)
	assert app.pan_x == 7 && app.pan_y == 3
	app.pan(-10000, -10000)
	assert app.pan_x == 0 && app.pan_y == 0
	app.key_input('\x1b[C')
	assert app.pan_x == 7
	app.pointer_event(.down, .left, 0, 10, preview_toolbar_height + 8, 1, 200)
	app.pointer_event(.move, .left, 0, 17, preview_toolbar_height + 8, 1, 200)
	assert app.pan_x == 0
	app.pointer_event(.up, .left, 0, 17, preview_toolbar_height + 8, 1, 200)
	assert !app.dragging
	app.set_zoom(9999)
	assert app.zoom == 400
	app.set_zoom(-1)
	assert app.zoom == 10
	app.fit_image()
	geometry := app.geometry()
	assert geometry.width <= 1 && geometry.height <= 1
	app.set_viewport(9999, 9999)
	assert app.viewport_width == 2048 && app.viewport_height == 2048
	app.set_viewport(2, 1)
	app.set_zoom(100)
	assert app.publish_surface() && !os.exists(first)
	begin_frame_elements()
	tree := app.build(ui2.rect(0, 0, 760, 560))!
	assert preview_test_has_action(tree, preview_action_open)
	assert preview_test_has_action(tree, preview_action_export_copy)
	free_tree(tree)
	last := app.surface_path.clone()
	app.close_app()
	app.close_app()
	assert !os.exists(last) && app.pixels == unsafe { nil }
	unsafe { last.free() }
}

fn test_preview_path_editing_keeps_complete_utf8_and_ignores_terminal_sequences() {
	mut app := PreviewApp{}
	defer { app.close_app() }
	preview_set_field(mut app.open_path, 'old')
	app.key_input('\x01')
	app.key_input('\xe6\x97')
	assert editor_bytes_text(app.open_path) == 'old'
	app.key_input('\xa5')
	assert editor_bytes_text(app.open_path) == '日'
	app.key_input('本😀\x7f')
	assert editor_bytes_text(app.open_path) == '日本'
	app.key_input('\x1b[1;5C')
	assert editor_bytes_text(app.open_path) == '日本'
	app.key_input('\x01')
	app.paste_input('/tmp/日本\n\r\x00.png')
	assert editor_bytes_text(app.open_path) == '/tmp/日本.png'
	app.key_input('\x01')
	app.paste_input('/tmp/\xff\xe6\x97日本.png')
	assert editor_bytes_text(app.open_path) == '/tmp/日本.png'
	app.key_input('\t')
	assert app.focus == .export_path
	app.paste_input('/tmp/export.png')
	assert editor_bytes_text(app.export_path) == '/tmp/export.png'
	app.key_input('\x01')
	large := 'x'.repeat(preview_max_path + 1)
	app.paste_input(large)
	unsafe { large.free() }
	assert editor_bytes_text(app.export_path) == '/tmp/export.png'
	app.key_input('\x15')
	assert app.export_path.len == 0
}

fn test_preview_maximum_png_export_and_viewport_are_bounded() {
	root := preview_test_root('maximum')
	defer { os.rmdir_all(root) or {} }
	path := join_path(root, 'maximum.png')
	mut pixels := []u8{len: preview_max_pixels * 4, init: 255}
	app := PreviewApp{ width: 4096, height: 2048, pixels: pixels.data }
	start := monotonic_millis()
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
	assert fd >= 0
	assert app.write_png(fd)
	assert desktop_close(fd) == 0
	elapsed := monotonic_millis() - start
	eprintln('Preview maximum-image PNG export: ${elapsed} ms')
	unsafe { pixels.free() }
	mut reopened := PreviewApp{}
	defer { reopened.close_app() }
	preview_set_field(mut reopened.open_path, path)
	assert reopened.open_image()
	assert reopened.width == 4096 && reopened.height == 2048
	reopened.set_viewport(760, 420)
	start_surface := monotonic_millis()
	assert reopened.publish_surface()
	eprintln('Preview 760x420 viewport: ${monotonic_millis() - start_surface} ms')
}

fn test_preview_decodes_jpeg_and_original_copy_preserves_jpeg_bytes() {
	root := preview_test_root('jpeg')
	defer { os.rmdir_all(root) or {} }
	path := join_path(root, 'image.jpg')
	image := base64.decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDwKiiivw8/04P/2Q==')
	defer { unsafe { image.free() } }
	os.write_file_array(path, image)!
	mut app := PreviewApp{}
	defer { app.close_app() }
	preview_set_field(mut app.open_path, path)
	assert app.open_image()
	assert app.width == 1 && app.height == 1
	assert unsafe { app.pixels[0] } > 240
	assert unsafe { app.pixels[1] } < 16
	assert unsafe { app.pixels[2] } < 16
	assert unsafe { app.pixels[3] } == 255
	copy_path := join_path(root, 'original.jpg')
	preview_set_field(mut app.export_path, copy_path)
	assert app.export_image(true)
	copy := os.read_bytes(copy_path)!
	assert copy == image
	unsafe { copy.free() }
}

fn test_preview_rejects_png_inflate_that_exceeds_its_header_dimensions() {
	root := preview_test_root('inflate')
	defer { os.rmdir_all(root) or {} }
	path := join_path(root, 'extra-pixels.png')
	pixels := []u8{len: 64 * 64 * 4, init: 255}
	preview_test_write_image(path, 64, 64, pixels)
	unsafe { pixels.free() }
	mut png := os.read_bytes(path)!
	preview_put_be32(png.data, 16, 1)
	preview_put_be32(png.data, 20, 1)
	os.write_file_array(path, png)!
	unsafe { png.free() }
	mut app := PreviewApp{}
	defer { app.close_app() }
	preview_set_field(mut app.open_path, path)
	assert !app.open_image()
	assert app.status_key == 'preview.status.cannot_decode'
	assert app.pixels == unsafe { nil }
	mut huge_chunk := base64.decode(preview_test_png)
	preview_put_be32(huge_chunk.data, 33, 0x80000000)
	os.write_file_array(path, huge_chunk)!
	unsafe { huge_chunk.free() }
	assert !app.open_image() && app.status_key == 'preview.status.cannot_decode'
	mut truncated := base64.decode(preview_test_png)
	truncated.trim(truncated.len - 2)
	os.write_file_array(path, truncated)!
	unsafe { truncated.free() }
	assert !app.open_image() && app.status_key == 'preview.status.cannot_decode'
}

fn test_preview_decodes_iphone_png_as_straight_rgba_and_exports_correct_colors() {
	root := preview_test_root('iphone')
	defer { os.rmdir_all(root) or {} }
	path := join_path(root, 'iphone.png')
	image := base64.decode('iVBORw0KGgoAAAAEQ2dCSQAAAACbUvlTAAAADUlIRFIAAAACAAAAAQgGAAAA9CJ/igAAAAtJREFUY2BgaGhg+M/wHwC1zGX7AAAAAElFTkSuQmCC')
	os.write_file_array(path, image)!
	unsafe { image.free() }
	mut app := PreviewApp{}
	defer { app.close_app() }
	preview_set_field(mut app.open_path, path)
	assert app.open_image()
	assert app.width == 2 && app.height == 1
	assert unsafe { app.pixels[0] } == 255
	assert unsafe { app.pixels[1] } == 0
	assert unsafe { app.pixels[2] } == 0
	assert unsafe { app.pixels[3] } == 128
	assert unsafe { app.pixels[5] } == 255
	output := join_path(root, 'converted.png')
	preview_set_field(mut app.export_path, output)
	assert app.export_image(false)
	mut reopened := PreviewApp{}
	defer { reopened.close_app() }
	preview_set_field(mut reopened.open_path, output)
	assert reopened.open_image()
	for index in 0 .. 8 {
		assert unsafe { reopened.pixels[index] } == unsafe { app.pixels[index] }
	}
}

fn preview_test_fail_crop_allocation(_ usize) &u8 { return unsafe { nil } }

fn preview_test_control(element ui2.Element, action string) ?ui2.Element {
	if element.id == action { return element }
	for child in element.children {
		if found := preview_test_control(child, action) { return found }
	}
	return none
}

fn test_preview_selection_maps_fit_zoom_pan_centered_viewports_and_clamped_drag() {
	pixels := []u8{len: 100 * 50 * 4}
	defer { unsafe { pixels.free() } }
	mut app := PreviewApp{width: 100, height: 50, pixels: pixels.data,
		viewport_width: 800, viewport_height: 400}
	app.set_tool(.select)
	body_height := preview_toolbar_height + preview_status_height + 400
	app.pointer_event(.down, .left, 0, 280, preview_toolbar_height + 140, 800, body_height)
	assert app.selection.anchor_x == 20 && app.selection.anchor_y == 10
	assert app.pointer_moves_matter() && !app.dragging
	app.pointer_event(.move, .left, 0, 439, preview_toolbar_height + 199, 800, body_height)
	assert app.crop_rect() == PreviewCropRect{left: 20, top: 10, width: 40, height: 15}
	// Release coordinates complete the selection even without a final move.
	app.pointer_event(.up, .left, 0, 479, preview_toolbar_height + 219, 800, body_height)
	assert app.crop_rect() == PreviewCropRect{left: 20, top: 10, width: 50, height: 20}
	assert !app.pointer_moves_matter()
	app.pointer_event(.down, .left, 0, 10, preview_toolbar_height + 10, 800, body_height)
	assert !app.selection.active
	app.viewport_width = 120
	app.viewport_height = 60
	app.fit = false
	app.zoom = 200
	app.pan_x = 70
	app.pan_y = 40
	zoomed_height := preview_toolbar_height + preview_status_height + 60
	app.pointer_event(.down, .left, 0, 20, preview_toolbar_height + 10, 120, zoomed_height)
	assert app.selection.anchor_x == 45 && app.selection.anchor_y == 25
	app.pointer_event(.move, .left, 0, -1000000, 1000000, 120, zoomed_height)
	assert app.selection.caret_x == 0 && app.selection.caret_y == 49
	assert app.crop_rect_valid(app.crop_rect())
	app.pointer_event(.up, .left, 0, 1000000, -1000000, 120, zoomed_height)
	assert app.selection.caret_x == 99 && app.selection.caret_y == 0
	app.fit = true
	app.viewport_width = 2048
	app.viewport_height = 2048
	app.pan_x = 0
	app.pan_y = 0
	large_height := preview_toolbar_height + preview_status_height + 3000
	// 2048-square viewport centered in a 4096x3000 body; 400x200 image centered within it.
	pixel_x, pixel_y, inside := app.selection_pixel(2048, preview_toolbar_height + 1500,
		4096, large_height, false)
	assert inside && pixel_x == 50 && pixel_y == 25
	_, _, outside := app.selection_pixel(0, preview_toolbar_height, 4096, large_height, false)
	assert !outside
}

fn test_preview_crop_normalizes_every_exif_turn_preserves_alpha_and_original_source() {
	root := preview_test_root('crop-pixels')
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := files_child_path(root, 'input.png')
	exported := files_child_path(root, 'cropped.png')
	copied := files_child_path(root, 'original.png')
	defer { unsafe { path.free(); exported.free(); copied.free() } }
	pixels := [u8(10), 20, 30, 255, 40, 50, 60, 128, 70, 80, 90, 64,
		100, 110, 120, 0, 130, 140, 150, 192, 160, 170, 180, 255]
	defer { unsafe { pixels.free() } }
	preview_test_write_image(path, 2, 3, pixels)
	original := os.read_bytes(path)!
	defer { unsafe { original.free() } }
	for orientation in 1 .. 9 {
		for rotation in 0 .. 4 {
			os.write_file_array(path, original)!
			mut app := PreviewApp{}
			preview_set_field(mut app.open_path, path)
			assert app.open_image()
			app.orientation = orientation
			app.rotation = rotation
			app.set_viewport(2, 2)
			app.set_zoom(400)
			app.pan(-1, 1)
			app.tool = .select
			width, height := app.oriented_dimensions()
			app.selection = PreviewSelection{active: true, anchor_x: 1,
				caret_x: width - 1, caret_y: height - 2}
			before := app.crop_state()
			geometry := app.geometry()
			mut expected := []u8{len: (width - 1) * (height - 1) * 4}
			for y in 0 .. height - 1 {
				for x in 0 .. width - 1 {
					for channel in 0 .. 4 {
						expected[(y * (width - 1) + x) * 4 + channel] = unsafe {
							app.pixels[app.pixel_offset(x + 1, y) + channel] }
					}
				}
			}
			assert app.apply_crop()
			assert app.width == width - 1 && app.height == height - 1
			assert app.orientation == 1 && app.rotation == 0 && app.pixels_from_crop
			assert !app.selection.active && app.fit && app.pan_x == 0 && app.pan_y == 0
			assert app.source == original && app.loaded_path == path
			for index, byte in expected { assert unsafe { app.pixels[index] } == byte }
			cropped := app.crop_state()
			assert app.can_undo_crop() && !app.can_redo_crop()
			assert app.crop_history == before && cropped.pixels != before.pixels
			for _ in 0 .. 3 {
				assert app.undo_crop()
				assert app.crop_state() == before && app.geometry() == geometry
				assert !app.can_undo_crop() && app.can_redo_crop()
				for index, byte in pixels { assert unsafe { app.pixels[index] } == byte }
				assert app.source == original && app.loaded_path == path
				assert app.redo_crop()
				assert app.crop_state() == cropped
				for index, byte in expected { assert unsafe { app.pixels[index] } == byte }
			}
			preview_set_field(mut app.export_path, exported)
			assert app.export_image(false)
			mut reopened := PreviewApp{}
			preview_set_field(mut reopened.open_path, exported)
			assert reopened.open_image()
			assert reopened.width == width - 1 && reopened.height == height - 1
			for index, byte in expected { assert unsafe { reopened.pixels[index] } == byte }
			reopened.close_app()
			assert desktop_unlink(exported) == 0
			os.write_file(path, 'changed after cropping')!
			preview_set_field(mut app.export_path, copied)
			assert app.export_image(true)
			copy := os.read_bytes(copied)!
			assert copy == original
			assert desktop_unlink(copied) == 0
			unsafe { copy.free(); expected.free() }
			app.close_app()
			app.close_app()
		}
	}
}

fn test_preview_crop_failure_empty_invalid_bounds_and_cancel_preserve_image() {
	root := preview_test_root('crop-failures')
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := files_child_path(root, 'image.png')
	defer { unsafe { path.free() } }
	preview_test_fixture(path)
	mut app := PreviewApp{}
	defer { app.close_app() }
	assert !app.apply_crop()
	preview_set_field(mut app.open_path, path)
	assert app.open_image()
	old_pixels := app.pixels
	assert !app.apply_crop() && app.status_key == 'preview.status.selection_empty'
	app.selection = PreviewSelection{active: true, caret_x: 2}
	assert !app.apply_crop() && app.pixels == old_pixels
	app.selection = PreviewSelection{active: true, anchor_x: -1, caret_x: 0}
	assert !app.apply_crop() && app.pixels == old_pixels
	app.select_image()
	selection := app.selection
	assert !app.apply_crop_using(preview_test_fail_crop_allocation)
	assert app.status_key == 'preview.status.crop_failed'
	assert app.pixels == old_pixels && app.selection == selection
	assert app.width == 2 && app.height == 1 && !app.pixels_from_crop
	assert app.source.len > 0
	app.key_input('\x1b')
	assert !app.selection.active && app.pixels == old_pixels && app.focus == .image
	app.select_image()
	app.handle(preview_action_clear_selection)!
	assert !app.selection.active && app.pixels == old_pixels
	app.select_image()
	app.handle(preview_action_pan)!
	assert app.tool == .pan && !app.selection.active
}

fn test_preview_selection_keyboard_resets_pan_mode_and_visible_crop_controls() {
	root := preview_test_root('crop-controls')
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := files_child_path(root, 'image.png')
	defer { unsafe { path.free() } }
	preview_test_fixture(path)
	mut app := PreviewApp{}
	defer { app.close_app() }
	begin_frame_elements()
	mut tree := app.build(ui2.rect(0, 0, 800, 540))!
	for action in [preview_action_pan, preview_action_select, preview_action_crop,
		preview_action_clear_selection, preview_action_undo_crop, preview_action_redo_crop]! {
		control := preview_test_control(tree, action) or { panic('Missing Preview control') }
		assert !control.enabled && control.frame.x >= 0 && control.frame.x + control.frame.width <= 800
	}
	free_tree(tree)
	preview_set_field(mut app.open_path, path)
	assert app.open_image()
	begin_frame_elements()
	tree = app.build(ui2.rect(0, 0, 800, 540))!
	free_tree(tree)
	app.key_input('s\x01')
	assert app.tool == .select && app.selection.active
	begin_frame_elements()
	tree = app.build(ui2.rect(0, 0, 800, 540))!
	assert (preview_test_control(tree, preview_action_crop) or { panic('Missing Crop') }).enabled
	assert (preview_test_control(tree, preview_action_clear_selection) or { panic('Missing Clear') }).enabled
	assert (preview_test_control(tree, preview_action_select) or { panic('Missing Select') }).box.bg == catalina_control_accent
	assert (preview_test_control(tree, preview_action_pan) or { panic('Missing Pan') }).box.bg == body_panel
	free_tree(tree)
	app.key_input('\r')
	assert app.status_key == 'preview.status.cropped' && app.pixels_from_crop
	for body_width in [666, 800]! {
		begin_frame_elements()
		tree = app.build(ui2.rect(0, 0, body_width, 320))!
		undo := preview_test_control(tree, preview_action_undo_crop) or { panic('Missing Undo') }
		redo := preview_test_control(tree, preview_action_redo_crop) or { panic('Missing Redo') }
		assert undo.enabled && !redo.enabled
		assert undo.frame.x >= 0 && undo.frame.x + undo.frame.width <= redo.frame.x
		assert redo.frame.x + redo.frame.width <= body_width
		assert undo.frame.y + undo.frame.height < preview_toolbar_height
		free_tree(tree)
	}
	app.focus_field(.export_path)
	app.pending[0] = 0xe6
	app.pending_len = 1
	app.key_input('\x1a')
	assert app.focus == .image && app.pending_len == 0 && app.can_redo_crop()
	assert !app.pixels_from_crop && app.status_key == 'preview.status.crop_undone'
	begin_frame_elements()
	tree = app.build(ui2.rect(0, 0, 666, 320))!
	assert !(preview_test_control(tree, preview_action_undo_crop) or { panic('Missing Undo') }).enabled
	assert (preview_test_control(tree, preview_action_redo_crop) or { panic('Missing Redo') }).enabled
	free_tree(tree)
	app.key_input('\x19')
	assert app.pixels_from_crop && app.can_undo_crop() && app.status_key == 'preview.status.crop_redone'
	app.handle(preview_action_undo_crop)!
	assert app.can_redo_crop()
	app.handle(preview_action_redo_crop)!
	assert app.can_undo_crop()
	app.key_input('\x01')
	app.set_zoom(200)
	assert !app.selection.active
	app.select_image()
	app.rotate(1)
	assert !app.selection.active
	app.select_image()
	app.fit_image()
	assert !app.selection.active
	app.select_image()
	app.set_viewport(100, 100)
	assert !app.selection.active
	app.select_image()
	app.set_zoom(400)
	app.viewport_width = 1
	app.viewport_height = 1
	app.pan_x = 0
	app.pan_y = 0
	app.select_image()
	app.pan(1, 1)
	assert !app.selection.active
	app.key_input('p')
	assert app.tool == .pan
	app.pointer_event(.down, .left, 0, 10, preview_toolbar_height + 1, 100, 400)
	assert app.dragging
	app.pointer_event(.move, .left, 0, 9, preview_toolbar_height + 1, 100, 400)
	assert app.dragging
	app.pointer_event(.move, .left, 0, 8, preview_toolbar_height + 1, 100, 400)
	assert app.dragging
	app.pointer_event(.up, .left, 0, 8, preview_toolbar_height + 1, 100, 400)
	assert !app.dragging
	app.select_image()
	assert app.open_image() && !app.selection.active && app.tool == .pan
}

fn test_preview_crop_selection_surface_shades_outside_and_draws_a_border() {
	root := preview_test_root('crop-overlay')
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := files_child_path(root, 'image.png')
	defer { unsafe { path.free() } }
	pixels := []u8{len: 4 * 4 * 4, init: 255}
	preview_test_write_image(path, 4, 4, pixels)
	unsafe { pixels.free() }
	mut app := PreviewApp{}
	defer { app.close_app() }
	preview_set_field(mut app.open_path, path)
	assert app.open_image()
	app.set_viewport(16, 16)
	app.set_zoom(400)
	app.selection = PreviewSelection{active: true, anchor_x: 1, anchor_y: 1, caret_x: 2, caret_y: 2}
	assert app.publish_surface()
	surface := open_vinix_surface(app.surface_path) or { panic('Missing selection surface') }
	assert surface.pixel(0, 0) == 0x999999
	assert surface.pixel(4, 4) == catalina_control_accent
	assert surface.pixel(7, 7) == 0xffffff
	assert surface.pixel(11, 11) == catalina_control_accent
	surface.close()
	app.clear_selection()
	assert app.publish_surface()
	clear := open_vinix_surface(app.surface_path) or { panic('Missing cleared surface') }
	assert clear.pixel(0, 0) == 0xffffff && clear.pixel(4, 4) == 0xffffff
	clear.close()
}

fn test_preview_crop_history_replaces_one_step_and_survives_failed_open_or_crop() {
	root := preview_test_root('crop-history')
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := files_child_path(root, 'input.png')
	bad := files_child_path(root, 'missing.png')
	defer { unsafe { path.free(); bad.free() } }
	pixels := []u8{len: 8 * 6 * 4, init: u8(index % 256)}
	preview_test_write_image(path, 8, 6, pixels)
	unsafe { pixels.free() }
	mut app := PreviewApp{}
	defer { app.close_app() }
	assert !app.undo_crop() && !app.redo_crop()
	preview_set_field(mut app.open_path, path)
	assert app.open_image()
	app.select_image()
	app.selection.caret_x = 5
	assert app.apply_crop()
	assert app.width == 6 && app.height == 6
	first_pixels := app.pixels
	app.select_image()
	app.selection.anchor_x = 1
	app.selection.anchor_y = 1
	assert app.apply_crop()
	assert app.width == 5 && app.height == 5
	assert app.crop_history.pixels == first_pixels && app.crop_history.pixels_from_crop
	second_pixels := app.pixels
	assert app.undo_crop() && app.pixels == first_pixels
	assert app.width == 6 && app.height == 6 && !app.undo_crop()
	assert app.redo_crop() && app.pixels == second_pixels && !app.redo_crop()
	for undone in [false, true]! {
		if undone { assert app.undo_crop() }
		app.select_image()
		before := app.crop_state()
		history := app.crop_history
		assert !app.apply_crop_using(preview_test_fail_crop_allocation)
		assert app.crop_state() == before && app.crop_history == history && app.crop_undone == undone
		preview_set_field(mut app.open_path, bad)
		assert !app.open_image()
		assert app.crop_state() == before && app.crop_history == history && app.crop_undone == undone
		preview_set_field(mut app.open_path, path)
	}
	// A new crop after Undo discards the former Redo and starts one new step.
	assert app.pixels == first_pixels && app.can_redo_crop()
	app.selection = PreviewSelection{active: true, caret_x: 3, caret_y: 2}
	assert app.apply_crop()
	assert app.width == 4 && app.height == 3 && app.can_undo_crop() && !app.can_redo_crop()
	assert app.crop_history.pixels == first_pixels
	assert app.undo_crop() && app.pixels == first_pixels && app.width == 6
	assert app.redo_crop() && app.width == 4 && app.height == 3
	// Reopening clears history from either position, while keeping Open usable.
	for undone in [false, true]! {
		if undone { assert app.undo_crop() }
		assert app.open_image()
		assert !app.can_undo_crop() && !app.can_redo_crop()
		assert app.crop_history.pixels == unsafe { nil } && !app.pixels_from_crop
		assert app.width == 8 && app.height == 6
		app.select_image()
		assert app.apply_crop()
	}
	assert app.undo_crop()
	app.close_app()
	app.close_app()
	assert app.pixels == unsafe { nil } && app.crop_history.pixels == unsafe { nil }
}

fn test_preview_crop_history_restores_each_image_view_and_clamps_to_resized_window() {
	root := preview_test_root('crop-history-view')
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	path := files_child_path(root, 'input.png')
	defer { unsafe { path.free() } }
	preview_test_fixture(path)
	mut app := PreviewApp{}
	defer { app.close_app() }
	preview_set_field(mut app.open_path, path)
	assert app.open_image()
	app.orientation = 6
	app.rotate(1)
	app.set_viewport(1, 1)
	app.set_zoom(400)
	app.select_image()
	before := app.crop_state()
	assert app.apply_crop()
	app.rotate(1)
	app.set_zoom(200)
	app.set_tool(.pan)
	cropped_view := app.crop_state()
	assert app.undo_crop() && app.crop_state() == before
	assert !app.pointer_moves_matter()
	assert app.redo_crop() && app.crop_state() == cropped_view
	app.set_viewport(100, 100)
	assert app.undo_crop()
	assert app.width == before.width && app.height == before.height
	assert app.orientation == 6 && app.rotation == before.rotation && app.zoom == 400 && !app.fit
	assert app.viewport_width == 100 && app.viewport_height == 100
	assert app.pan_x == 0 && app.pan_y == 0
	assert app.geometry().left >= 0 && app.geometry().top >= 0
	assert app.publish_surface()
	assert app.redo_crop() && app.publish_surface()
}
