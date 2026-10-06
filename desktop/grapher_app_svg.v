// SPDX-License-Identifier: GPL-2.0-or-later
// Standalone vector output uses only a fixed stack buffer and borrowed labels.
module main

import math

struct GrapherSvgStream {
	fd int
mut:
	bytes [1024]u8
	length int
	ok bool = true
}

fn (mut stream GrapherSvgStream) flush() {
	if !stream.ok || stream.length == 0 { return }
	stream.ok = desktop_write_all(stream.fd, unsafe { &stream.bytes[0] }, u64(stream.length))
	stream.length = 0
}

fn (mut stream GrapherSvgStream) append(text string) {
	if !stream.ok { return }
	for ch in text {
		if stream.length == stream.bytes.len {
			stream.flush()
			if !stream.ok { return }
		}
		stream.bytes[stream.length] = ch
		stream.length++
	}
}

// XML 1.0 permits TAB, LF and CR but no other C0 controls, surrogates, or
// U+FFFE/U+FFFF. UTF-8 validation also rejects overlong and truncated sequences.
fn grapher_svg_text_valid(text string) bool {
	if text.len > 4096 || !grapher_valid_utf8(text) { return false }
	mut at := 0
	for at < text.len {
		ch := text[at]
		if ch < 32 && ch != 9 && ch != 10 && ch != 13 { return false }
		if at + 2 < text.len && ch == 0xef && text[at + 1] == 0xbf
			&& (text[at + 2] == 0xbe || text[at + 2] == 0xbf) { return false }
		at += editor_utf8_length(ch)
	}
	return true
}

fn (mut stream GrapherSvgStream) text(text string) {
	if !grapher_svg_text_valid(text) {
		stream.ok = false
		return
	}
	for ch in text {
		match ch {
			`&` { stream.append('&amp;') }
			`<` { stream.append('&lt;') }
			`>` { stream.append('&gt;') }
			`"` { stream.append('&quot;') }
			`'` { stream.append('&apos;') }
			else { stream.append(unsafe { tos(&ch, 1) }) }
		}
	}
}

fn (mut stream GrapherSvgStream) number(value f64) {
	if !math.is_finite(value) {
		stream.ok = false
		return
	}
	mut bytes := [64]u8{}
	length := unsafe { C.snprintf(&char(&bytes[0]), bytes.len, c'%.12g', value) }
	if length <= 0 || length >= bytes.len {
		stream.ok = false
		return
	}
	// Refuse locale decimal separators and any nonnumeric C formatting result.
	for index in 0 .. length {
		ch := bytes[index]
		if (ch < `0` || ch > `9`) && ch != `.` && ch != `-` && ch != `+`
			&& ch != `e` && ch != `E` {
			stream.ok = false
			return
		}
	}
	stream.append(unsafe { tos(&bytes[0], length) })
}

fn (mut stream GrapherSvgStream) label(x int, y int, size int, anchor string, color string, prefix string, text string) {
	stream.append('<text x="')
	stream.number(f64(x))
	stream.append('" y="')
	stream.number(f64(y))
	stream.append('" font-size="')
	stream.number(f64(size))
	stream.append('" text-anchor="')
	stream.text(anchor)
	stream.append('" fill="')
	stream.text(color)
	stream.append('">')
	stream.text(prefix)
	stream.text(text)
	stream.append('</text>\n')
}

fn (mut stream GrapherSvgStream) tick(value f64, x int, y int, anchor string) {
	if !math.is_finite(value) {
		stream.ok = false
		return
	}
	mut bytes := [64]u8{}
	length := unsafe { C.snprintf(&char(&bytes[0]), bytes.len, c'%.5g', value) }
	if length <= 0 || length >= bytes.len {
		stream.ok = false
		return
	}
	stream.label(x, y, 12, anchor, '#667085', '', unsafe { tos(&bytes[0], length) })
}

fn (mut stream GrapherSvgStream) point(x f64, y f64) {
	stream.number(x)
	stream.append(' ')
	stream.number(y)
}

fn grapher_svg_y(value f64, minimum f64, maximum f64) f64 {
	// Clamp before subtracting: a valid sample can be as large as 1e308.
	bounded := if value < minimum { minimum } else if value > maximum { maximum } else { value }
	return f64(grapher_png_plot_y) + (maximum - bounded) / (maximum - minimum) *
		f64(grapher_png_plot_height - 1)
}

struct GrapherSvgSegment {
	x1 f64
	y1 f64
	x2 f64
	y2 f64
}

fn grapher_svg_fraction(left f64, right f64, bound f64) f64 {
	// Halving before subtracting also handles finite samples near +/-1e308.
	return (bound * 0.5 - left * 0.5) / (right * 0.5 - left * 0.5)
}

fn (app &GrapherApp) svg_segment(index int) ?GrapherSvgSegment {
	left, right := app.values[index - 1], app.values[index]
	if !left.valid || !right.valid || !app.connect[index] { return none }
	minimum, maximum := app.range[2], app.range[3]
	if (left.value < minimum && right.value < minimum)
		|| (left.value > maximum && right.value > maximum) { return none }
	mut start := 0.0
	mut end := 1.0
	if left.value < minimum { start = grapher_svg_fraction(left.value, right.value, minimum) }
	if left.value > maximum { start = grapher_svg_fraction(left.value, right.value, maximum) }
	if right.value < minimum { end = grapher_svg_fraction(left.value, right.value, minimum) }
	if right.value > maximum { end = grapher_svg_fraction(left.value, right.value, maximum) }
	if !math.is_finite(start) || !math.is_finite(end) || start < 0 || start > end || end > 1 { return none }
	step := f64(grapher_png_plot_width - 1) / f64(grapher_sample_count - 1)
	return GrapherSvgSegment{
		x1: f64(grapher_png_plot_x) + (f64(index - 1) + start) * step
		y1: grapher_svg_y(left.value, minimum, maximum)
		x2: f64(grapher_png_plot_x) + (f64(index - 1) + end) * step
		y2: grapher_svg_y(right.value, minimum, maximum)
	}
}

fn (app &GrapherApp) svg_model_valid() bool {
	if !app.plotted || app.dirty || !grapher_range_valid(app.range[0], app.range[1])
		|| !grapher_range_valid(app.range[2], app.range[3]) { return false }
	for value in app.values {
		if value.valid && !math.is_finite(value.value) { return false }
	}
	for text in [app.field_text(0), tr('app.grapher'), tr('grapher.radians'), tr(app.status)]! {
		if !grapher_svg_text_valid(text) { return false }
	}
	return true
}

fn (app &GrapherApp) write_graph_svg(fd int) bool {
	if !app.svg_model_valid() { return false }
	mut stream := GrapherSvgStream{fd: fd}
	stream.append('<?xml version="1.0" encoding="UTF-8"?>\n')
	stream.append('<svg xmlns="http://www.w3.org/2000/svg" width="960" height="640" viewBox="0 0 960 640">\n')
	stream.append('<title>')
	stream.text(tr('app.grapher'))
	stream.append('</title>\n<desc>y = ')
	stream.text(app.field_text(0))
	stream.append('</desc>\n<rect width="960" height="640" fill="#ffffff"/>\n')
	stream.append('<defs><clipPath id="plot"><rect x="110" y="110" width="822" height="440"/></clipPath>')
	stream.append('<clipPath id="expression"><rect x="68" y="50" width="864" height="30"/></clipPath></defs>\n')
	stream.append('<g font-family="sans-serif">\n')
	stream.label(28, 40, 24, 'start', '#273142', '', tr('app.grapher'))
	stream.label(28, 73, 14, 'start', '#273142', '', 'y =')
	stream.append('<g clip-path="url(#expression)">')
	stream.label(68, 73, 14, 'start', '#273142', '', app.field_text(0))
	stream.append('</g>\n')
	stream.label(28, 98, 12, 'start', '#667085', '', tr('grapher.radians'))
	stream.append('<g clip-path="url(#plot)" fill="none" stroke-width="1">\n<path id="grid" stroke="#e5e7eb" d="')
	for index in 1 .. 10 {
		x := f64(grapher_png_plot_x + grapher_png_plot_width * index / 10)
		y := f64(grapher_png_plot_y + grapher_png_plot_height * index / 10)
		stream.append('M')
		stream.point(x, 110)
		stream.append('V550 M110 ')
		stream.number(y)
		stream.append('H932 ')
	}
	stream.append('"/>\n<path id="axes" stroke="#97a1b0" d="')
	if app.range[0] <= 0 && app.range[1] >= 0 {
		x := f64(grapher_png_plot_x) - app.range[0] / (app.range[1] - app.range[0]) *
			f64(grapher_png_plot_width - 1)
		stream.append('M')
		stream.point(x, 110)
		stream.append('V550 ')
	}
	if app.range[2] <= 0 && app.range[3] >= 0 {
		stream.append('M110 ')
		stream.number(grapher_svg_y(0, app.range[2], app.range[3]))
		stream.append('H932 ')
	}
	stream.append('"/>\n<path id="curve" stroke="#1671d9" stroke-width="2" stroke-linecap="round" d="')
	step := f64(grapher_png_plot_width - 1) / f64(grapher_sample_count - 1)
	for index in 1 .. grapher_sample_count {
		segment := app.svg_segment(index) or { continue }
		// Each sampled segment starts its own subpath. Domain gaps and rejected
		// connections cannot accidentally join when other samples are skipped.
		stream.append('M')
		stream.point(segment.x1, segment.y1)
		stream.append('L')
		stream.point(segment.x2, segment.y2)
		stream.append(' ')
	}
	stream.append('"/>\n<g id="samples" fill="#1671d9" stroke="none">\n')
	for index in 0 .. grapher_sample_count {
		value := app.values[index]
		if !value.valid || value.value < app.range[2] || value.value > app.range[3] { continue }
		if index > 0 && app.connect[index] { continue }
		stream.append('<circle cx="')
		stream.number(f64(grapher_png_plot_x) + f64(index) * step)
		stream.append('" cy="')
		stream.number(grapher_svg_y(value.value, app.range[2], app.range[3]))
		stream.append('" r="1"/>\n')
	}
	stream.append('</g></g>\n<rect x="109" y="109" width="824" height="442" fill="none" stroke="#e5e7eb"/>\n')
	stream.tick(app.range[3], 98, 123, 'end')
	stream.tick(app.range[2], 98, 550, 'end')
	stream.tick(app.range[0], 110, 579, 'start')
	stream.tick(app.range[1], 932, 579, 'end')
	stream.label(28, 334, 14, 'start', '#273142', '', 'y')
	stream.label(521, 602, 14, 'middle', '#273142', '', 'x')
	stream.label(28, 629, 12, 'start', '#667085', '', tr(app.status))
	stream.append('</g></svg>\n')
	stream.flush()
	return stream.ok
}

fn (mut app GrapherApp) export_svg() {
	app.document_status = ''
	app.export_status = ''
	if app.dirty || !app.plotted {
		if !app.plot() { return }
	}
	path := app.field_text(8)
	if !grapher_document_path_valid(path) {
		app.export_status = 'grapher.svg_invalid'
		return
	}
	parent, leaf := archive_parent(path)
	if parent < 0 {
		app.export_status = 'grapher.svg_failed'
		return
	}
	defer {
		desktop_close(parent)
		unsafe { leaf.free() }
	}
	fd := C.openat(parent, &char(leaf.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0o600)
	if fd < 0 {
		app.export_status = if C.errno == C.EEXIST { 'grapher.svg_exists' } else { 'grapher.svg_failed' }
		return
	}
	mut identity := C.stat{}
	identified := unsafe { C.fstat(fd, &identity) } == 0
	written := identified && app.write_graph_svg(fd) && desktop_preferences_fsync(fd)
		&& archive_sync_parent(parent, fd)
	closed := desktop_close(fd) == 0
	if !written || !closed {
		mut current := C.stat{}
		// Only unlink our failed creation; retain a concurrently replaced name.
		if identified && unsafe { C.fstatat(parent, &char(leaf.str), &current, C.AT_SYMLINK_NOFOLLOW) } == 0
			&& current.st_dev == identity.st_dev && current.st_ino == identity.st_ino {
			C.unlinkat(parent, &char(leaf.str), 0)
		}
		app.export_status = 'grapher.svg_failed'
		return
	}
	app.export_status = 'grapher.svg_saved'
}
