// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.base64
import os
import ui2

fn quicklook_tree_has_action(element ui2.Element, action string) bool {
	if element.id == action {
		return true
	}
	for child in element.children {
		if quicklook_tree_has_action(child, action) {
			return true
		}
	}
	return false
}

fn quicklook_tree_has_preview_image(element ui2.Element) bool {
	if element.image_path.starts_with(vinix_preview_image_prefix) {
		return true
	}
	for child in element.children {
		if quicklook_tree_has_preview_image(child) {
			return true
		}
	}
	return false
}

fn quicklook_entry_index(entries []FileEntry, name string) int {
	for index, entry in entries {
		if entry.name == name { return index }
	}
	return -1
}

fn test_files_quicklook_text_from_list_and_column_selection() {
	root := os.join_path(os.temp_dir(), 'vinix-files-quicklook-text-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	os.write_file(os.join_path(root, 'notes.py'), 'first\nsecond\nthird\n') or { panic(err) }

	mut app := FilesContextApp{}
	app.files.browser.read(root.clone())
	index := quicklook_entry_index(app.files.browser.entries, 'notes.py')
	assert index >= 0
	app.handle(app.files.browser.entries[index].row_action)!
	assert app.files.browser.selected_row == index
	app.key_input(' ')
	assert app.preview.open && app.preview.kind == .text
	assert app.preview.lines == ['first', 'second', 'third']
	assert app.preview.path == os.join_path(root, 'notes.py')
	view := app.build(ui2.rect(0, 0, 700, 400))!
	assert quicklook_tree_has_action(view, files_quicklook_close)
	free_tree(view)
	app.key_input('\x1b')
	assert !app.preview.open

	app.handle(files_action_view_columns)!
	column := app.files.columns.len - 1
	row := quicklook_entry_index(app.files.columns[column].browser.entries, 'notes.py')
	assert row >= 0
	app.handle(app.files.columns[column].browser.entries[row].row_action)!
	assert app.files.columns[column].selected_row == row
	app.key_input(' ')
	assert app.preview.open && app.preview.lines[0] == 'first'
	app.key_input(' ')
	assert !app.preview.open
	app.close_app()
	app.files.free_miller_columns()
	app.files.browser.free_entries()
	unsafe {
		app.files.browser.path.free()
		app.context_path.free()
	}
}

fn test_files_quicklook_decodes_png_into_a_shared_surface() {
	root := os.join_path(os.temp_dir(), 'vinix-files-quicklook-image-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	path := os.join_path(root, 'picture.png')
	// Two RGBA pixels: opaque red and half-transparent green.
	image := base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAD0lEQVR4nGP4z8DwHwgbABB5A359Y87XAAAAAElFTkSuQmCC')
	os.write_file_array(path, image) or { panic(err) }
	mut preview := FilesQuickLook{}
	preview.show(path)
	assert preview.open && preview.kind == .image
	assert preview.message == ''
	assert preview.image_width == 2 && preview.image_height == 1
	surface_path := preview.surface_path.clone()
	surface := open_vinix_surface(surface_path) or { panic('preview surface was not readable') }
	assert surface.pixel(0, 0) == 0xff0000
	assert surface.pixel(1, 0) == 0x7fff7f
	surface.close()
	view := preview.build(ui2.rect(0, 0, 400, 260))
	assert quicklook_tree_has_preview_image(view)
	free_tree(view)
	mut cache := VinixPreviewCache{}
	mut canvas := new_scaled_canvas(6, 4, 6, 4, 1)
	defer {
		cache.clear()
		unsafe { free(canvas.pixels) }
	}
	canvas.clear(0x123456)
	assert cache.draw(mut canvas, surface_path, 1, 1, 4, 2)
	assert canvas.logical_pixel(1, 1) == 0xff0000
	assert canvas.logical_pixel(4, 2) == 0x7fff7f
	assert canvas.logical_pixel(0, 0) == 0x123456
	cached_pixels := cache.pixels
	canvas.clear(0x123456)
	canvas.clip = Clip{ x: 2, y: 1, w: 1, h: 1 }
	assert cache.draw(mut canvas, surface_path, 1, 1, 4, 2)
	assert cache.pixels == cached_pixels
	assert canvas.logical_pixel(1, 1) == 0x123456
	assert canvas.logical_pixel(2, 1) != 0x123456
	assert canvas.logical_pixel(3, 1) == 0x123456
	mut hidpi := new_scaled_canvas(6, 4, 12, 8, 2)
	defer { unsafe { free(hidpi.pixels) } }
	hidpi.clear(0x123456)
	assert cache.draw(mut hidpi, surface_path, 1, 1, 4, 2)
	assert unsafe { hidpi.pixels[2 * hidpi.stride + 2] } == 0xff0000
	assert unsafe { hidpi.pixels[3 * hidpi.stride + 3] } == 0xff0000
	assert unsafe { hidpi.pixels[5 * hidpi.stride + 9] } == 0x7fff7f
	canvas.clip = Clip{ x: 0, y: 0, w: 6, h: 4 }
	assert cache.draw(mut canvas, surface_path, 1, 1, 2, 1)
	assert cache.width == 2 && cache.height == 1
	preview.close()
	assert !os.exists(surface_path)
	preview.show(path)
	assert preview.message == '' && preview.surface_path != surface_path
	assert cache.draw(mut canvas, preview.surface_path, 1, 1, 2, 1)
	assert cache.path == preview.surface_path
	preview.close()
	unsafe { surface_path.free() }
}

fn test_files_quicklook_decodes_jpeg() {
	root := os.join_path(os.temp_dir(), 'vinix-files-quicklook-jpeg-test')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	path := os.join_path(root, 'photo.jpg')
	// A 1x1 red JPEG. Exact channels vary slightly with JPEG rounding.
	encoded := '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDwKiiivw8/04P/2Q=='
	os.write_file_array(path, base64.decode(encoded)) or { panic(err) }
	mut preview := FilesQuickLook{}
	preview.show(path)
	assert preview.open && preview.kind == .image && preview.message == ''
	surface := open_vinix_surface(preview.surface_path) or { panic('JPEG preview surface was not readable') }
	color := surface.pixel(0, 0)
	assert (color >> 16) & 0xff > 200
	assert (color >> 8) & 0xff < 40
	assert color & 0xff < 40
	surface.close()
	preview.close()
}

fn test_files_quicklook_only_opens_supported_regular_files() {
	assert files_quicklook_kind('IMAGE.JPG') == .image
	assert files_quicklook_kind('stereo.jps') == .image
	assert files_quicklook_kind('script.py') == .text
	assert files_quicklook_kind('archive.zip') == .none_
	mut preview := FilesQuickLook{}
	preview.show('/tmp/does-not-exist.txt')
	assert preview.open && preview.message != ''
	preview.close()
	root := os.join_path(os.temp_dir(), 'vinix-files-quicklook-folder.txt')
	os.rmdir_all(root) or {}
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	preview.show(root)
	assert preview.open && preview.message != ''
	preview.close()
}
