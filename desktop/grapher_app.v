// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <stdio.h>

const grapher_field_actions = ['grapher.expression', 'grapher.xmin', 'grapher.xmax', 'grapher.ymin',
	'grapher.ymax', 'grapher.path', 'grapher.document_path', 'grapher.png_path']!
const grapher_field_limit = 512

struct GrapherField {
mut:
	bytes []u8
}

struct GrapherApp {
mut:
	fields         [8]GrapherField
	initialized    bool
	focus          int = -1
	selected       bool
	pending        [4]u8
	pending_length int
	program        GrapherProgram
	values         [grapher_sample_count]GrapherValue
	connect        [grapher_sample_count]bool
	range          [4]f64
	plotted        bool
	dirty          bool
	status         string
	export_status  string
	document_status string
}

fn open_grapher_app(mut _ Desktop) !NativeApp {
	mut app := &GrapherApp{}
	app.initialize()
	return app
}

fn (mut app GrapherApp) initialize() {
	app.close_app()
	for index in 0 .. app.fields.len {
		app.fields[index].bytes = []u8{cap: grapher_field_limit}
		unsafe { app.fields[index].bytes.flags |= .noslices }
	}
	app.initialized = true
	app.set_field(0, 'sin(x)')
	app.reset_ranges()
	home := if desktop_user_home.len > 0 { desktop_user_home } else { desktop_home }
	path := grapher_default_export_path(home)
	app.set_field(5, path)
	unsafe { path.free() }
	document := grapher_default_path(home, 'graph.vgraph')
	app.set_field(6, document)
	unsafe { document.free() }
	image := grapher_default_path(home, 'graph.png')
	app.set_field(7, image)
	unsafe { image.free() }
	app.plot()
}

fn grapher_default_export_path(home string) string {
	return grapher_default_path(home, 'graph.csv')
}

fn grapher_default_path(home string, name string) string {
	if home.len == 0 || home.len > 4096 || home.index_u8(0) >= 0 { return '' }
	// Resolve the compositor's trusted personal folder alias once. Typed export
	// paths still refuse links in every component. V3's os.real_path promotes
	// its scratch buffer; this explicitly unsafe address keeps ours on stack.
	terminated := home.clone()
	defer { unsafe { terminated.free() } }
	mut bytes := [4096]u8{}
	if unsafe { C.realpath(&char(terminated.str), &char(&bytes[0])) } == unsafe { nil } {
		return ''
	}
	mut length := 0
	for length < bytes.len && bytes[length] != 0 { length++ }
	if length == bytes.len || length + name.len + 1 > grapher_field_limit { return '' }
	canonical := unsafe { tos(&bytes[0], length) }.clone()
	defer { unsafe { canonical.free() } }
	return disk_utility_join_path(canonical, name)
}

fn (app &GrapherApp) field_text(index int) string {
	return editor_bytes_text(app.fields[index].bytes)
}

fn (mut app GrapherApp) set_field(index int, text string) {
	app.fields[index].bytes.clear()
	for ch in text { app.fields[index].bytes << ch }
	if index < 5 { app.dirty = true }
	app.export_status = ''
	app.document_status = ''
}

fn (mut app GrapherApp) reset_ranges() {
	for index, value in ['-10', '10', '-5', '5']! { app.set_field(index + 1, value) }
}

fn (mut app GrapherApp) plot() bool {
	app.export_status = ''
	app.document_status = ''
	program := grapher_parse(app.field_text(0)) or {
		app.plotted = false
		app.status = 'grapher.expression_invalid'
		return false
	}
	mut range := [4]f64{}
	for index in 0 .. 4 {
		range[index] = grapher_constant(app.field_text(index + 1)) or {
			app.plotted = false
			app.status = 'grapher.range_invalid'
			return false
		}
	}
	if !grapher_range_valid(range[0], range[1]) || !grapher_range_valid(range[2], range[3]) {
		app.plotted = false
		app.status = 'grapher.range_invalid'
		return false
	}
	app.program = program
	app.range = range
	step := (range[1] - range[0]) / f64(grapher_sample_count - 1)
	mut valid := 0
	for index in 0 .. grapher_sample_count {
		app.values[index] = program.evaluate(range[0] + f64(index) * step)
		app.connect[index] = false
		if app.values[index].valid { valid++ }
		if index > 0 {
			app.connect[index] = grapher_connect(&program, app.values[index - 1], app.values[index],
				range[0] + f64(index - 1) * step, step, range[3] - range[2])
		}
	}
	app.plotted = true
	app.dirty = false
	app.status = if valid == 0 {
		'grapher.no_values'
	} else if valid < grapher_sample_count {
		'grapher.domain_gaps'
	} else {
		'grapher.ready'
	}
	app.export_status = ''
	return true
}

fn grapher_number(value f64) string {
	mut buffer := [64]u8{}
	length := unsafe { C.snprintf(&char(&buffer[0]), 64, c'%.17g', value) }
	return unsafe { tos(&buffer[0], if length > 0 && length < 64 { length } else { 0 }).clone() }
}

fn (mut app GrapherApp) zoom(factor f64) {
	if !app.plot() { return }
	mut range := [4]f64{}
	for axis in 0 .. 2 {
		middle := (app.range[axis * 2] + app.range[axis * 2 + 1]) * 0.5
		half := (app.range[axis * 2 + 1] - app.range[axis * 2]) * 0.5 * factor
		range[axis * 2] = middle - half
		range[axis * 2 + 1] = middle + half
		if !grapher_range_valid(range[axis * 2], range[axis * 2 + 1]) {
			app.status = 'grapher.range_invalid'
			return
		}
	}
	for index, value in range {
		text := grapher_number(value)
		app.set_field(index + 1, text)
		unsafe { text.free() }
	}
	app.plot()
}

fn (mut app GrapherApp) handle(id string) ! {
	for index, action in grapher_field_actions {
		if id == action {
			app.focus = index
			app.selected = true
			app.pending_length = 0
			return
		}
	}
	match id {
		'grapher.plot' { app.plot() }
		'grapher.reset' {
			app.reset_ranges()
			app.plot()
		}
		'grapher.zoom_in' { app.zoom(0.5) }
		'grapher.zoom_out' { app.zoom(2) }
		'grapher.export' { app.export_csv() }
		'grapher.export_png' { app.export_png() }
		'grapher.document_open' { app.open_graph_document() }
		'grapher.document_save_as' { app.save_graph_document() }
		else {}
	}
}

fn (mut app GrapherApp) input_text(text string) {
	if app.focus < 0 || app.focus >= app.fields.len { return }
	limit := if app.focus == 0 {
		grapher_expression_limit
	} else if app.focus >= 5 {
		grapher_field_limit
	} else {
		64
	}
	current := if app.selected { 0 } else { app.fields[app.focus].bytes.len }
	if current + text.len > limit {
		app.export_status = ''
		app.document_status = ''
		app.status = 'grapher.input_limit'
		return
	}
	if app.selected {
		app.fields[app.focus].bytes.clear()
		app.selected = false
	}
	for ch in text { app.fields[app.focus].bytes << ch }
	if app.focus < 5 {
		app.dirty = true
		app.status = 'grapher.changed'
	}
	app.export_status = ''
	app.document_status = ''
}

fn (mut app GrapherApp) input_byte(ch u8) {
	if app.pending_length > 0 {
		if editor_utf8_follows(app.pending[0], app.pending_length, ch) {
			app.pending[app.pending_length] = ch
			app.pending_length++
			if app.pending_length == editor_utf8_length(app.pending[0]) {
				app.input_text(unsafe { tos(&app.pending[0], app.pending_length) })
				app.pending_length = 0
			}
			return
		}
		app.pending_length = 0
	}
	if ch == 8 || ch == 127 {
		if app.focus < 0 { return }
		if app.selected {
			app.fields[app.focus].bytes.clear()
			app.selected = false
		} else {
			mut end := app.fields[app.focus].bytes.len - 1
			for end > 0 && app.fields[app.focus].bytes[end] & 0xc0 == 0x80 { end-- }
			if end >= 0 { app.fields[app.focus].bytes.trim(end) }
		}
		if app.focus < 5 {
			app.dirty = true
			app.status = 'grapher.changed'
		}
		app.export_status = ''
		app.document_status = ''
	} else if ch >= 32 && ch < 127 {
		app.input_text(unsafe { tos(&ch, 1) })
	} else if app.focus >= 5 && editor_utf8_length(ch) > 1 {
		app.pending[0] = ch
		app.pending_length = 1
	}
}

fn (mut app GrapherApp) key_input(text string) {
	if text.len > 1 && text[0] == 0x1b { return }
	for ch in text {
		match ch {
			0x01 {
				if app.focus >= 0 {
					app.selected = true
					app.pending_length = 0
				}
			}
			0x0c {
				app.focus = 0
				app.selected = true
				app.pending_length = 0
			}
			0x1b {
				app.focus = -1
				app.pending_length = 0
			}
			`\t` {
				app.focus = (app.focus + 1) % app.fields.len
				app.selected = true
				app.pending_length = 0
			}
			`\r`, `\n` {
				app.pending_length = 0
				if app.focus == 7 {
					app.export_png()
				} else if app.focus == 6 {
					app.open_graph_document()
				} else if app.focus == 5 {
					app.export_csv()
				} else {
					app.plot()
				}
			}
			else {
				if app.focus >= 0 { app.input_byte(ch) }
			}
		}
	}
}

fn (mut app GrapherApp) paste_input(text string) {
	if app.focus < 0 { return }
	// Reject rather than merge pasted multi-line expressions or invalid UTF-8.
	if !grapher_valid_utf8(text) {
		app.export_status = ''
		app.document_status = ''
		app.status = 'grapher.input_invalid'
		return
	}
	for ch in text {
		if ch < 32 || ch == 127 || (app.focus < 5 && ch >= 128) {
			app.export_status = ''
			app.document_status = ''
			app.status = 'grapher.input_invalid'
			return
		}
	}
	app.pending_length = 0
	app.input_text(text)
}

fn grapher_valid_utf8(text string) bool {
	mut at := 0
	for at < text.len {
		length := editor_utf8_length(text[at])
		if length == 0 || at + length > text.len { return false }
		for offset in 1 .. length {
			if !editor_utf8_follows(text[at], offset, text[at + offset]) { return false }
		}
		at += length
	}
	return true
}

fn (app &GrapherApp) csv() []u8 {
	mut bytes := []u8{cap: 65536}
	unsafe { bytes.flags |= .noslices }
	disk_usage_append(mut bytes, 'x,y\n')
	step := (app.range[1] - app.range[0]) / f64(grapher_sample_count - 1)
	for index in 0 .. grapher_sample_count {
		x := grapher_number(app.range[0] + f64(index) * step)
		disk_usage_append(mut bytes, x)
		unsafe { x.free() }
		bytes << `,`
		if app.values[index].valid {
			y := grapher_number(app.values[index].value)
			disk_usage_append(mut bytes, y)
			unsafe { y.free() }
		}
		bytes << `\n`
	}
	return bytes
}

fn (mut app GrapherApp) export_csv() {
	app.document_status = ''
	if app.dirty || !app.plotted {
		if !app.plot() { return }
	}
	if !app.plotted { return }
	path := app.field_text(5)
	if !archive_absolute_valid(path) {
		app.export_status = 'grapher.export_invalid'
		return
	}
	// Share Archive's anchored component walk: parent and leaf are owned here.
	parent, leaf := archive_parent(path)
	if parent < 0 {
		app.export_status = 'grapher.export_failed'
		return
	}
	defer {
		desktop_close(parent)
		unsafe { leaf.free() }
	}
	fd := C.openat(parent, &char(leaf.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0o600)
	if fd < 0 {
		app.export_status = if C.errno == C.EEXIST {
			'grapher.export_exists'
		} else {
			'grapher.export_failed'
		}
		return
	}
	mut identity := C.stat{}
	identified := C.fstat(fd, &identity) == 0
	bytes := app.csv()
	written := identified && desktop_write_all(fd, bytes.data, u64(bytes.len)) && desktop_preferences_fsync(fd) && archive_sync_parent(parent, fd)
	unsafe { bytes.free() }
	closed := desktop_close(fd) == 0
	if !written || !closed {
		mut current := C.stat{}
		// A replacement at this name belongs to someone else; retain it.
		if identified && C.fstatat(parent, &char(leaf.str), &current, C.AT_SYMLINK_NOFOLLOW) == 0
			&& current.st_dev == identity.st_dev && current.st_ino == identity.st_ino {
			C.unlinkat(parent, &char(leaf.str), 0)
		}
		app.export_status = 'grapher.export_failed'
		return
	}
	app.export_status = 'grapher.export_saved'
}

fn (mut app GrapherApp) close_app() {
	for index in 0 .. app.fields.len {
		if app.fields[index].bytes.cap > 0 { unsafe { app.fields[index].bytes.free() } }
		app.fields[index].bytes = []u8{}
	}
	app.initialized = false
	app.focus = -1
	app.selected = false
	app.pending_length = 0
	app.plotted = false
	app.status = ''
	app.export_status = ''
	app.document_status = ''
}
