// SPDX-License-Identifier: GPL-2.0-or-later
// Compiled beside the actual Software app by distribution-check.v.
module main

import json2
import os
import ui2

struct Desktop {
	tz_offset_seconds i64
}

interface NativeApp {
mut:
	build(ui2.Rect) !ui2.Element
	handle(string) !
}

const console_filter_limit = 256
const body_text = u32(0x111111)
const body_panel = u32(0xeeeeee)
const settings_choice_bg = u32(0xccccff)
const app_surface = u32(0xffffff)
const workflow_owned_text_key = 'owned'

fn editor_bytes_text(bytes []u8) string { return unsafe { tos(bytes.data, bytes.len) } }

fn console_sanitize(text string) string { return text.clone() }

fn console_backspace(mut bytes []u8, selected bool) {
	if selected {
		bytes.clear()
	} else if bytes.len > 0 {
		bytes.delete_last()
	}
}

fn console_paste_field(mut bytes []u8, text string, limit int, selected bool) {
	if selected { bytes.clear() }
	for byte in text { if bytes.len < limit && byte >= 32 { bytes << byte } }
}

fn console_field(id string, text string, x int, y int, width int, _ bool) ui2.Element {
	return ui2.button(id, text, ui2.rect(f64(x), f64(y), f64(width), 28), ui2.BoxStyle{}, ui2.TextStyle{})
}

fn frame_elements(capacity int) []ui2.Element { return []ui2.Element{cap: capacity} }

fn main() {
	mut app := SoftwareApp{ query: []u8{cap: 256}, output: []u8{cap: 8192} }
	view := SoftwareView{
		format:       1
		architecture: 'aarch64'
		rows:         [
			SoftwareRow{ id: 'editor', name: 'Editor', description: 'Write text documents', version: '2.0.0', installed_version: '1.0.0', requested: true, updatable: true, repository: 'trusted', public_key: 'a'.repeat(64), permissions: ['files'] },
			SoftwareRow{ id: 'browser', name: 'Browser', description: 'Browse websites', version: '1.0.0' },
			SoftwareRow{ id: 'runtime', name: 'Runtime', description: 'Shared runtime', installed_version: '1.0.0' },
			SoftwareRow{ id: 'blocked', name: 'Blocked', description: 'License required', version: '1.0.0', diagnostic: 'License acceptance required' },
		]
	}
	encoded := json2.encode(view)
	for byte in encoded { app.output << byte }
	app.load_view()
	// Reload frees the previous decoded permissions and transfers fresh rows.
	app.load_view()
	assert app.rows.len == 4
	assert app.matching.len == 4
	app.handle('software.installed') or { panic(err) }
	assert app.matching == [0, 2]
	app.handle('software.updates') or { panic(err) }
	assert app.matching == [0]
	app.handle('software.catalog') or { panic(err) }
	app.handle('software.search') or { panic(err) }
	app.key_input('websites')
	assert app.matching == [1]
	app.key_input('\x01')
	app.key_input('text')
	assert app.matching == [0]
	app.handle('software.row.0') or { panic(err) }
	assert app.selected == 0
	app.handle('software.install') or { panic(err) }
	assert app.review == 'install'
	app.handle('software.cancel') or { panic(err) }
	assert app.review == ''
	app.selected = 2
	app.handle('software.remove') or { panic(err) }
	assert app.status.contains('dependency')
	app.selected = 3
	app.handle('software.install') or { panic(err) }
	assert app.review == ''
	assert app.status == 'License acceptance required'
	tail := software_output_tail('old progress\nolder progress\nnew progress\nchecksum mismatch\nretry from trusted repository\n'.bytes())
	assert !tail.contains('old progress')
	assert tail.contains('checksum mismatch')
	assert tail.ends_with('retry from trusted repository')
	app.selected = 0
	tree := app.build(ui2.rect(0, 0, 900, 660)) or { panic(err) }
	assert tree.children.any(it.id == 'software.search')
	assert tree.children.any(it.id == 'software.remove')
	assert tree.children.any(it.id == 'software.refresh')
	compact := app.build(ui2.rect(0, 0, 480, 300)) or { panic(err) }
	assert compact.children.len == 2
	assert !compact.children.any(it.id == 'software.install')
	app.worker = os.new_process(os.find_abs_path_of_executable('false') or { panic(err) })
	app.worker.set_args(['owned worker argument'.clone()])
	app.worker.wait()
	assert app.worker.code == 1
	assert !app.prepare_close()
	app.retire_worker()
	assert app.prepare_close()
	app.close_app()
	println('Software UI: search, installed/updates filters, provenance, permission review, removal diagnostics and close guard passed')
}
