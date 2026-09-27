// SPDX-License-Identifier: GPL-2.0-or-later
// Space opens a bounded, read-only preview in the Files window. Images are
// decoded in the Files process and handed to the compositor as a VSF1 surface.
module main

import ui2

#flag -DSTB_IMAGE_IMPLEMENTATION -DSTBI_ONLY_JPEG -DSTBI_ONLY_PNG -DSTBI_ONLY_BMP -DSTBI_ONLY_GIF -DSTBI_NO_STDIO -DSTBI_NO_SIMD
#include "stb_image.h"

fn C.stbi_info_from_memory(buffer &u8, length int, width &int, height &int, channels &int) int
fn C.stbi_load_from_memory(buffer &u8, length int, width &int, height &int, channels &int, desired_channels int) &u8
fn C.stbi_image_free(buffer voidptr)

const files_quicklook_close = 'files.quicklook.close'
const files_quicklook_max_source = u64(32 * 1024 * 1024)
const files_quicklook_max_pixels = 32 * 1024 * 1024
const files_quicklook_surface_pixels = 4 * 1024 * 1024
const files_quicklook_max_text = u64(128 * 1024)
const files_quicklook_max_lines = 1024
const files_quicklook_line_height = 17

enum FilesQuickLookKind {
	none_
	image
	text
}

struct FilesQuickLook {
mut:
	open         bool
	kind         FilesQuickLookKind
	path         string
	surface_path string
	image_width  int
	image_height int
	lines        []string
	scroll       int
	message      string
	truncated    bool
}

fn files_quicklook_kind(path string) FilesQuickLookKind {
	lower := path.to_lower()
	defer { unsafe { lower.free() } }
	if lower.ends_with('.png') || lower.ends_with('.jpg') || lower.ends_with('.jpeg')
		|| lower.ends_with('.jpe') || lower.ends_with('.jps') || lower.ends_with('.bmp')
		|| lower.ends_with('.gif') {
		return .image
	}
	for extension in ['.txt', '.py', '.v', '.c', '.h', '.cpp', '.hpp', '.js', '.ts', '.json', '.md',
		'.html', '.css', '.sh', '.yml', '.yaml', '.toml', '.xml', '.csv', '.log', '.ini', '.rs',
		'.go', '.java', '.rb', '.sql'] {
		if lower.ends_with(extension) {
			return .text
		}
	}
	return .none_
}

fn (mut p FilesQuickLook) close() {
	if p.surface_path.len > 0 {
		desktop_unlink(p.surface_path)
		unsafe { p.surface_path.free() }
	}
	if p.path.len > 0 {
		unsafe { p.path.free() }
	}
	if p.lines.cap > 0 {
		unsafe { p.lines.free() }
	}
	if p.message.len > 0 {
		unsafe { p.message.free() }
	}
	p.surface_path = ''
	p.path = ''
	p.lines = []string{}
	p.message = ''
	p.kind = .none_
	p.scroll = 0
	p.image_width = 0
	p.image_height = 0
	p.truncated = false
	p.open = false
}

fn files_quicklook_put_u32(mut bytes []u8, at int, value u32) {
	for shift in 0 .. 4 {
		bytes[at + shift] = u8(value >> (shift * 8))
	}
}

fn (mut p FilesQuickLook) load_image() bool {
	info := desktop_stat(p.path) or { return false }
	if info.is_dir || info.size == 0 || info.size > files_quicklook_max_source {
		return false
	}
	mut source := []u8{len: int(info.size)}
	defer { unsafe { source.free() } }
	if desktop_read_file(p.path, source.data, info.size) != i64(info.size) {
		return false
	}
	mut width := 0
	mut height := 0
	mut channels := 0
	if C.stbi_info_from_memory(source.data, source.len, &width, &height, &channels) == 0
		|| width <= 0 || height <= 0 || width > 8192 || height > 8192
		|| i64(width) * i64(height) > files_quicklook_max_pixels {
		return false
	}
	pixels := C.stbi_load_from_memory(source.data, source.len, &width, &height, &channels, 4)
	if pixels == unsafe { nil } {
		return false
	}
	defer { C.stbi_image_free(pixels) }
	mut output_width := width
	mut output_height := height
	for output_width > 2048 || output_height > 2048
		|| output_width * output_height > files_quicklook_surface_pixels {
		output_width = if output_width > 1 { output_width / 2 } else { 1 }
		output_height = if output_height > 1 { output_height / 2 } else { 1 }
	}
	stride := output_width * 4
	buffer_size := stride * output_height
	mut surface := []u8{len: 48 + buffer_size}
	defer { unsafe { surface.free() } }
	files_quicklook_put_u32(mut surface, 0, vinix_surface_magic)
	files_quicklook_put_u32(mut surface, 4, vinix_surface_version)
	files_quicklook_put_u32(mut surface, 8, u32(vinix_surface_header_size))
	files_quicklook_put_u32(mut surface, 12, u32(output_width))
	files_quicklook_put_u32(mut surface, 16, u32(output_height))
	files_quicklook_put_u32(mut surface, 20, u32(stride))
	files_quicklook_put_u32(mut surface, 24, vinix_surface_format_xrgb8888)
	files_quicklook_put_u32(mut surface, 40, u32(buffer_size))
	for y in 0 .. output_height {
		for x in 0 .. output_width {
			input_at := ((y * height / output_height) * width + x * width / output_width) * 4
			output_at := (y * output_width + x) * 4
			alpha := int(unsafe { pixels[input_at + 3] })
			for color in 0 .. 3 {
				value := int(unsafe { pixels[input_at + color] })
				composed := u8((value * alpha + 255 * (255 - alpha)) / 255)
				// VSF1 is little-endian XRGB8888, so the byte order is B, G, R, 0.
				surface[48 + output_at + (2 - color)] = composed
			}
		}
	}
	path := '/tmp/vinix-files-preview-${C.getpid()}.surface'
	fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
	if fd < 0 {
		unsafe { path.free() }
		return false
	}
	written := desktop_write_all(fd, surface.data, u64(surface.len))
		&& desktop_write_all(fd, unsafe { &surface[48] }, u64(buffer_size))
	ok := desktop_close(fd) == 0 && written
	if !ok {
		desktop_unlink(path)
		unsafe { path.free() }
		return false
	}
	p.surface_path = path
	p.image_width = output_width
	p.image_height = output_height
	return true
}

fn (mut p FilesQuickLook) load_text() bool {
	info := desktop_stat(p.path) or { return false }
	if info.is_dir {
		return false
	}
	limit := if info.size > files_quicklook_max_text { files_quicklook_max_text } else { info.size }
	if limit == 0 {
		return true
	}
	mut source := []u8{len: int(limit)}
	defer { unsafe { source.free() } }
	got := desktop_read_file(p.path, source.data, limit)
	if got < 0 {
		return false
	}
	p.truncated = info.size > limit
	mut line := []u8{cap: 240}
	defer { unsafe { line.free() } }
	for index in 0 .. int(got) {
		ch := source[index]
		if ch == `\n` {
			p.lines << line.bytestr()
			line.clear()
			if p.lines.len >= files_quicklook_max_lines {
				p.truncated = true
				break
			}
			continue
		}
		if ch == `\r` {
			continue
		}
		if ch == `\t` {
			for _ in 0 .. 4 {
				if line.len < 240 { line << ` ` }
			}
		} else if line.len < 240 {
			line << if ch < 32 || ch == 127 { ` ` } else { ch }
		}
	}
	if line.len > 0 && p.lines.len < files_quicklook_max_lines {
		p.lines << line.bytestr()
	}
	return true
}

fn (mut p FilesQuickLook) show(path string) {
	p.close()
	p.kind = files_quicklook_kind(path)
	if p.kind == .none_ {
		return
	}
	p.path = path.clone()
	p.open = true
	ok := match p.kind {
		.image { p.load_image() }
		.text { p.load_text() }
		.none_ { false }
	}
	if !ok {
		p.message = 'Unable to preview this file.'
	}
}

fn files_quicklook_panel(size ui2.Rect) (int, int, int, int) {
	width := int(size.width)
	height := int(size.height)
	margin := if width < 400 || height < 260 { 12 } else { 30 }
	return margin, margin, width - margin * 2, height - margin * 2
}

fn (p &FilesQuickLook) visible_lines(height int) int {
	_, _, _, panel_height := files_quicklook_panel(ui2.rect(0, 0, 500, f64(height)))
	count := (panel_height - 62) / files_quicklook_line_height
	return if count > 1 { count } else { 1 }
}

fn (mut p FilesQuickLook) scroll_by(delta int, height int) {
	if !p.open || p.kind != .text {
		return
	}
	maximum := p.lines.len - p.visible_lines(height)
	p.scroll = files_clamp(p.scroll + delta, if maximum > 0 { maximum } else { 0 })
}

fn (p &FilesQuickLook) build(size ui2.Rect) ui2.Element {
	x, y, width, height := files_quicklook_panel(size)
	mut body := frame_elements(4 + p.visible_lines(int(size.height)))
	body << ui2.label('', file_path_name(p.path), ui2.rect(18, 8, f64(width - 70), 27), ui2.TextStyle{
		color: body_heading
		size:  15
		bold:  true
	})
	body << ui2.button(files_quicklook_close, '×', ui2.rect(f64(width - 36), 10, 24, 24),
		ui2.BoxStyle{ bg: body_panel, radius: 5 }, ui2.TextStyle{
			color: body_text
			size:  17
			align: .center
		})
	body << ui2.view('', ui2.rect(0, 42, f64(width), 1), ui2.BoxStyle{ bg: body_rule }, [])
	if p.message != '' {
		body << ui2.label('', p.message, ui2.rect(18, 62, f64(width - 36), 24), ui2.TextStyle{
			color: files_error
			size:  13
		})
	} else if p.kind == .image {
		available_width := width - 32
		available_height := height - 60
		mut image_width := available_width
		mut image_height := available_height
		if p.image_width * available_height < p.image_height * available_width {
			image_width = p.image_width * available_height / p.image_height
		} else {
			image_height = p.image_height * available_width / p.image_width
		}
		body << ui2.image('', '${vinix_surface_image_prefix}${p.surface_path}', ui2.rect(f64((width - image_width) / 2), f64(50 + (available_height - image_height) / 2),
			f64(image_width), f64(image_height)))
	} else {
		mut text_children := frame_elements(p.visible_lines(int(size.height)) + 1)
		for row := 0; row < p.visible_lines(int(size.height)); row++ {
			index := p.scroll + row
			if index >= p.lines.len { break }
			text_children << ui2.label('', p.lines[index], ui2.rect(0, f64(row * files_quicklook_line_height),
				f64(width - 40), files_quicklook_line_height), ui2.TextStyle{ color: body_text, size: 12 })
		}
		body << ui2.view('', ui2.rect(20, 52, f64(width - 40), f64(height - 72)),
			ui2.BoxStyle{ transparent: true }, text_children)
		if p.truncated {
			body << ui2.label('', 'Showing the beginning of the file', ui2.rect(20, f64(height - 20),
				f64(width - 40), 16), ui2.TextStyle{ color: body_muted, size: 11 })
		}
	}
	mut children := frame_elements(2)
	children << ui2.view('', ui2.rect(0, 0, size.width, size.height), ui2.BoxStyle{
		bg: 0x35404f
	}, [])
	children << ui2.view('', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg:     0xffffff
		radius: 9
	}, body)
	return ui2.view('', ui2.rect(0, 0, size.width, size.height), ui2.BoxStyle{
		transparent: true
	}, children)
}

fn (mut a FilesContextApp) quicklook_move_selection(delta int) {
	if a.files.view_mode == .list {
		count := a.files.browser.entries.len
		if count == 0 { return }
		current := a.files.browser.selected_row
		next := files_clamp(current + delta, count - 1)
		a.files.browser.selected_row = next
		path := join_path(a.files.browser.path, a.files.browser.entries[next].name)
		a.set_context_path(path)
		unsafe { path.free() }
		a.focus_path(a.context_path)
		return
	}
	if a.files.columns.len == 0 { return }
	index := a.files.columns.len - 1
	count := a.files.columns[index].browser.entries.len
	if count == 0 { return }
	current := a.files.columns[index].selected_row
	next := files_clamp(current + delta, count - 1)
	a.files.columns[index].selected_row = next
	path := join_path(a.files.columns[index].browser.path, a.files.columns[index].browser.entries[next].name)
	a.set_context_path(path)
	unsafe { path.free() }
	a.focus_path(a.context_path)
}

fn (mut a FilesContextApp) quicklook_key_input(input string) {
	if a.rename_path.len > 0 { return }
	mut index := 0
	for index < input.len {
		ch := input[index]
		if ch == 0x1b && index + 2 < input.len && input[index + 1] == `[` {
			code := input[index + 2]
			if code == `A` || code == `B` {
				if a.preview.open {
					a.preview.scroll_by(if code == `A` { -1 } else { 1 }, a.files.rows_height + files_header_height)
				} else {
					a.quicklook_move_selection(if code == `A` { -1 } else { 1 })
				}
				index += 3
				continue
			}
		}
		if a.preview.open {
			if ch == ` ` || ch == 0x1b {
				a.preview.close()
			}
		} else if ch == ` ` && a.context_path.len > 0 {
			a.preview.show(a.context_path)
		}
		index++
	}
}
