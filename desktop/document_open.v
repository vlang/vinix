// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import ui2
import desktop.workflowcore

const document_open_magic = u32(0x444f504e)

struct DocumentOpenRequest { path string app string use_default bool }

interface DocumentOpeningApp {
mut:
	take_document_open_request() []u8
}

fn document_associations() map[string]string {
	store := files_job_store() or { return map[string]string{} }
	defer { unsafe { store.free() } }
	bytes := workflowcore.read_regular(store + '/associations.json', 65536) or { return map[string]string{} }
	defer { unsafe { bytes.free() } }
	return json2.decode[map[string]string](bytes.bytestr()) or { map[string]string{} }
}

fn workflow_default_app(path string) string {
	if info := desktop_stat(path) { if info.is_dir { return 'vinix-files' } }
	ext := os.file_ext(path).to_lower()
	defer { unsafe { ext.free() } }
	if ext == '.vgraph' { return 'vinix-grapher' }
	if ext in ['.zip', '.tar', '.gz', '.bz2', '.xz', '.tgz', '.7z', '.rar']! { return 'vinix-archive' }
	if ext in ['.png', '.jpg', '.jpeg', '.jpe', '.jps', '.gif', '.bmp', '.pdf', '.docx', '.xlsx', '.pptx', '.odt', '.ods', '.odp', '.epub', '.doc', '.xls', '.ppt', '.rtf', '.mp4', '.mkv', '.webm', '.mov', '.avi', '.mp3', '.wav', '.ogg', '.flac', '.m4a']! { return 'vinix-preview' }
	return 'vinix-editor'
}

fn (mut d Desktop) open_workflow_document(path string) {
	associations := document_associations()
	defer { unsafe { associations.free() } }
	ext := os.file_ext(path).to_lower()
	defer { unsafe { ext.free() } }
	name := d.session_document_app(path, associations[ext] or { workflow_default_app(path) })
	for i, factory in available_apps { if factory.process_name == name { d.open_path_in_app(i, path); return } }
}

fn native_app_document_request(mut app NativeApp) []u8 {
	if mut app is DocumentOpeningApp {
		mut opener := &DocumentOpeningApp(app)
		defer { unsafe { free(opener) } }
		return opener.take_document_open_request()
	}
	return []u8{}
}

fn (mut a FilesContextApp) queue_document_open(path string, app string) {
	if !workflowcore.valid_path(path) || C.access(&char(path.str), C.R_OK) != 0 { a.operation_error('Document is unavailable or permission denied.'); return }
	unsafe { a.document_request.free() }
	a.document_request = json2.encode(DocumentOpenRequest{path: path, app: app, use_default: app.len > 0 && a.document_default})
}

fn (mut a FilesContextApp) take_document_open_request() []u8 {
	if a.document_request.len == 0 { return []u8{} }
	mut bytes := []u8{cap: 8 + a.document_request.len}
	wire_put_u32(mut bytes, document_open_magic)
	wire_put_u32(mut bytes, u32(a.document_request.len))
	for ch in a.document_request { bytes << ch }
	unsafe { a.document_request.free() }
	a.document_request = ''
	return bytes
}

fn (mut app RemoteApp) handle_document_open(data string) bool {
	if !app.desktop_services || app.desktop == unsafe { nil } || data.len < 8 || data.len > 8192 || color_meter_read_u32(data, 0) != document_open_magic || int(color_meter_read_u32(data, 4)) != data.len - 8 { return false }
	text := unsafe { tos(&data.str[8], data.len - 8) }
	request := json2.decode[DocumentOpenRequest](text) or { return false }
	defer { unsafe { request.path.free(); request.app.free() } }
	if !workflowcore.valid_path(request.path) || C.access(&char(request.path.str), C.R_OK) != 0 { return false }
	if request.use_default && app.desktop.session_sender_has_gesture(app.pid) {
		app.desktop.session_associate_document(request.path, request.app)
	}
	if request.app.len == 0 { app.desktop.open_workflow_document(request.path) }
	else { for i, factory in available_apps { if factory.process_name == request.app { app.desktop.open_path_in_app(i, request.path); break } } }
	return true
}

fn (mut a FilesContextApp) document_open_action(action string) bool {
	if action == 'files.document.open' {
		path := if a.preview.open { a.preview.path } else { a.context_path }
		a.queue_document_open(path, '')
		return true
	}
	if action == 'files.document.choose' { a.document_choose = true; return true }
	if action == 'files.document.back' { a.document_choose = false; return true }
	if action == 'files.document.default' { a.document_default = !a.document_default; return true }
	if !action.starts_with('files.document.app.') { return false }
	i := action['files.document.app.'.len..].int()
	if i < 0 || i >= available_apps.len { return true }
	path := a.context_path
	if a.document_default && path.len > 0 {
		mut associations := document_associations()
		ext := os.file_ext(path).to_lower()
		associations[ext] = available_apps[i].process_name
		store := files_job_store() or { a.operation_error(err.msg()); return true }
		encoded := json2.encode(associations)
		workflowcore.atomic_save(store + '/associations.json', encoded.bytes(), workflowcore.SaveOptions{}) or { a.operation_error(err.msg()) }
		unsafe { associations.free(); ext.free(); store.free(); encoded.free() }
	}
	a.queue_document_open(path, available_apps[i].process_name)
	a.document_choose = false
	return true
}

fn (a &FilesContextApp) document_open_panel(size ui2.Rect) ui2.Element {
	mut rows := frame_elements(20)
	rows << ui2.button('files.document.back', 'Back', ui2.rect(8, 8, 100, 28), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 12})
	rows << ui2.button('files.document.default', if a.document_default { '✓ Use by default for this type' } else { 'Use by default for this type' }, ui2.rect(116, 8, 300, 28), ui2.BoxStyle{bg: body_panel}, ui2.TextStyle{color: body_text, size: 12})
	rows << ui2.label('', a.context_path, ui2.rect(8, 44, size.width - 16, 26), ui2.TextStyle{color: body_text, size: 12})
	mut row := 0
	for i, factory in available_apps {
		if factory.process_name !in ['vinix-editor', 'vinix-preview', 'vinix-archive', 'vinix-files', 'vinix-grapher', 'vinix-notes'] { continue }
		number := i.str()
		defer { unsafe { number.free() } }
		rows << workflow_button('files.document.app.' + number, factory.title, ui2.rect(8, f64(80 + row * 36), size.width - 16, 32), false)
		row++
	}
	return ui2.screen(app_surface, rows)
}
