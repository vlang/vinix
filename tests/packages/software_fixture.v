// SPDX-License-Identifier: GPL-2.0-or-later
// Compiled beside the actual Software app by distribution-check.v.
module main

import json2
import os
import ui2
import time
import desktop.packagecore
import tools.packages.pkgprotocol
import tools.packages.appsdk

$if track_heap ? {
	#include "tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

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
const app_accent = u32(0x4060b0)
const body_rule = u32(0xcccccc)
const workflow_owned_text_key = 'owned'
const workflow_owned_id_text_key = 'owned-id-text'

fn editor_bytes_text(bytes []u8) string {
	if bytes.len == 0 { return '' }
	return unsafe { tos(bytes.data, bytes.len) }
}

fn console_sanitize(text string) string { return text.clone() }

fn console_backspace(mut bytes []u8, selected bool) {
	if selected {
		bytes.clear()
	} else if bytes.len > 0 {
		for bytes.len > 1 && bytes[bytes.len - 1] & 0xc0 == 0x80 { bytes.delete_last() }
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

fn fixture_review(operation string, names []string) pkgprotocol.Review {
	return pkgprotocol.Review{
		format: 1, operation: operation, names: names, architecture: 'aarch64', generation: 3,
		target_generation: if operation == 'rollback' { u64(2) } else { u64(0) },
		fingerprint: 'c'.repeat(64), requested: ['editor'], disk_needed: 4096, disk_available: 65536, disk_reserve: 1024,
		rows: [
			pkgprotocol.ReviewPackage{ id: 'editor', name: 'Editor', description: 'Write documents', version: if operation == 'repair' { '1.0.0' } else { '2.0.0' }, installed_version: '1.0.0', architecture: 'aarch64', kind: 'linux', runtime: 'runtime', repository: 'trusted', public_key: 'a'.repeat(64), license: 'MIT', permissions: ['files'], requested: true, action: 'update' },
			pkgprotocol.ReviewPackage{ id: 'runtime', name: 'Runtime', description: 'Required shared runtime', version: if operation == 'repair' { '1.0.0' } else { '2.0.0' }, installed_version: '1.0.0', architecture: 'aarch64', kind: 'runtime', repository: 'runtime-publisher', public_key: 'b'.repeat(64), license: 'Vendor-EULA', proprietary: true, firmware: true, permissions: ['network', 'process'], action: 'update' },
		]
	}
}

fn wait_for_software(mut app SoftwareApp) {
	// Sanitized child startup can exceed half a second on a shared build host.
	// Keep completion bounded while requiring the same worker exit/admission.
	for _ in 0 .. 5000 {
		app.poll()
		if app.worker == unsafe { nil } { return }
		time.sleep(time.millisecond)
	}
	panic('Software fixture service did not finish')
}

fn check_package_review() {
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192},
		rows: [SoftwareRow{ id: 'editor', requested: true, installed_version: '1.0.0' }] }
	app.selected = 0
	app.handle('software.install') or { panic(err) }
	assert app.worker_review && !app.review_ready
	assert app.prepare_close(), 'a read-only review is safe to close'
	pending := app.build(ui2.rect(0, 0, 900, 660)) or { panic(err) }
	assert !pending.children.any(it.id == 'software.confirm')
	app.handle('software.confirm') or { panic(err) }
	assert app.worker_review
	wait_for_software(mut app)
	assert app.review_ready && app.review_snapshot.rows.len == 2
	app.handle('software.row.1') or { panic(err) }
	assert app.review_selected == 1 && app.selected == 0
	tree := app.build(ui2.rect(0, 0, 900, 660)) or { panic(err) }
	assert tree.children.any(it.id == 'software.row.1' && it.text == 'update: Runtime')
	assert tree.children.any(it.text.contains('runtime-publisher'))
	assert tree.children.any(it.text.contains('Permissions: network, process'))
	assert tree.children.any(it.text.contains('Vendor-EULA (proprietary)') && it.text.contains('firmware'))
	assert tree.children.any(it.text.contains('4 KiB needed') && it.text.contains('1 KiB reserved'))
	assert tree.children.any(it.id == 'software.confirm')
	assert !tree.children.any(it.id == 'software.install' || it.id == 'software.run')
	// Confirmation is tied to the returned intent, not the current list selection.
	app.selected = -1
	app.handle('software.confirm') or { panic(err) }
	assert !app.review_ready && app.worker != unsafe { nil }
	assert !app.prepare_close()
	wait_for_software(mut app)
	assert app.status.contains('stale') && app.review == ''
	assert app.review_snapshot.rows.len == 0
	// Each supported maintenance action goes through asynchronous plan review.
	for action in ['software.upgrade', 'software.rollback'] {
		app.handle(action) or { panic(err) }
		wait_for_software(mut app)
		assert app.review_ready
		if action == 'software.rollback' { assert app.status.contains('new generation') && app.status.contains('undo it') }
		app.handle('software.cancel') or { panic(err) }
		assert app.review_snapshot.rows.len == 0 && app.review_summary == ''
	}
	app.begin_review('install', ['broken'])
	wait_for_software(mut app)
	assert !app.review_ready && app.status.contains('dependency unavailable')
	app.begin_review('install', ['wrong-format'])
	wait_for_software(mut app)
	assert !app.review_ready && app.status.contains('Unsupported')
	app.begin_review('install', ['wrong-intent'])
	wait_for_software(mut app)
	assert !app.review_ready && app.status.contains('different package operation')
	// The preview list pages independently of the underlying catalog selection.
	a_snapshot := fixture_review('upgrade', [])
	mut rows := a_snapshot.rows.clone()
	for i in 0 .. 20 {
		rows << pkgprotocol.ReviewPackage{ ...a_snapshot.rows[1], id: 'z-runtime-' + i.str(), name: 'Additional runtime' }
	}
	app.review = 'upgrade'.clone()
	app.review_snapshot = json2.decode[pkgprotocol.Review](json2.encode(pkgprotocol.Review{ ...a_snapshot, rows: rows })) or { panic(err) }
	app.review_ready = true
	app.build(ui2.rect(0, 0, 900, 660)) or { panic(err) }
	app.handle('software.down') or { panic(err) }
	assert app.review_scroll > 0
	app.handle('software.row.0') or { panic(err) }
	assert app.review_selected == app.review_scroll
	app.handle('software.up') or { panic(err) }
	assert app.review_scroll == 0
	app.close_app()
}

fn software_window_child(id string) {
	if id == 'memo' { software_window_text_child(); return }
	assert id == 'counter'
	mut count := 0
	mut sequence := u64(1)
	for {
		frame := appsdk.WindowFrame{ sequence: sequence, title: 'Counter', width: 320, height: 160,
			background: 0xffffff, elements: [
				appsdk.WindowElement{ kind: 'label', id: '', text: 'Count: ' + count.str(), x: 12, y: 12, width: 280, height: 24, color: 0x111111, background: 0 },
				appsdk.WindowElement{ kind: 'button', id: 'increase', text: 'Increase', x: 12, y: 48, width: 120, height: 28, color: 0, background: 0xe0e0ff },
				appsdk.WindowElement{ kind: 'button', id: 'software.confirm', text: 'Application-owned action', x: 12, y: 92, width: 280, height: 28, color: 0, background: 0xe0e0ff },
			] }
		println(appsdk.window_prefix + (frame.encode() or { panic(err) }))
		flush_stdout()
		mut event := appsdk.read_window_event() or { panic(err) }
		if event.kind == 'close' { event.close(); return }
		assert event.kind == 'click' && event.id == 'increase' && event.sequence == sequence
		event.close()
		count++; sequence++
	}
}

fn wait_window_frame(mut app SoftwareApp, sequence u64) ! {
	for _ in 0 .. 500 {
		app.poll()
		if app.window_frame.sequence == sequence { return }
		time.sleep(time.millisecond)
	}
	return error('native window frame timed out: ' + app.status)
}

fn free_window_tree(tree ui2.Element) {
	for child in tree.children { free_window_tree(child) }
	unsafe {
		if tree.key in [workflow_owned_text_key, workflow_owned_id_text_key]! { tree.text.free() }
		if tree.key == workflow_owned_id_text_key { tree.id.free() }
		(&array(&tree.children)).free()
	}
}

fn check_software_window() ! {
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192},
		rows: [SoftwareRow{ id: 'counter', installed_version: '1.0.0', installed_kind: 'native', installed_window_protocol: 1 }] }
	app.launch_request = json2.encode(packagecore.Request{ id: 'counter' })
	app.run_requested()
	assert app.window_mode && app.worker_run && app.worker.args == ['run-window', 'counter']
	wait_window_frame(mut app, 1)!
	tree := app.build(ui2.rect(0, 0, 900, 660))!
	assert tree.children.any(it.text == 'Count: 0')
	assert tree.children.any(it.id == software_window_action + 'increase')
	assert tree.children.any(it.id == software_window_action + 'software.confirm')
	assert !tree.children.any(it.id == 'software.confirm')
	free_window_tree(tree)
	app.handle('software.confirm')!
	assert app.window_frame.sequence == 1 && app.worker.args == ['run-window', 'counter']
	app.handle(software_window_action + 'increase')!
	wait_window_frame(mut app, 2)!
	assert app.window_frame.elements[0].text == 'Count: 1'
	assert !app.prepare_close() && app.window_closing
	wait_for_software(mut app)
	assert app.prepare_close() && app.window_mode && app.status.contains('finished')
	app.close_app()
	mut detached := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192} }
	detached.open_window(packagecore.Request{ id: 'counter' }, 1)!
	wait_window_frame(mut detached, 1)!
	pid := detached.worker.pid
	detached.close_app()
	mut status := 0
	assert C.waitpid(pid, &status, 0) == pid && status == 0
	mut parser := SoftwareApp{ window_mode: true, window_pending: []u8{cap: appsdk.window_frame_limit + appsdk.window_prefix.len} }
	text := appsdk.WindowFrame{ sequence: 1, title: 'Parser', width: 64, height: 64 }.encode()!
	line := appsdk.window_prefix + text + '\n'
	for byte in line {
		one := byte.ascii_str()
		parser.window_output(one)
		unsafe { one.free() }
	}
	assert parser.window_frame.sequence == 1
	parser.window_output(appsdk.window_prefix + '{"format":2}\n')
	assert parser.window_frame.sequence == 1 && parser.window_failure.contains('Invalid')
	parser.window_output('x'.repeat(appsdk.window_frame_limit + appsdk.window_prefix.len + 1))
	assert parser.window_skip && parser.window_pending.len == 0
	parser.window_output('\n')
	assert !parser.window_skip && parser.window_failure.contains('size limit')
	parser.window_output(line)
	assert parser.window_frame.sequence == 1
	unsafe { text.free(); line.free() }
	parser.close_app()
	// Exercise the same atomic write against a pipe with no reader draining it.
	mut pipe := [2]i32{} // C pipe descriptors have a fixed 32-bit width
	assert C.pipe(&pipe[0]) == 0
	mut blocked := SoftwareApp{ window_writable: true, worker: os.new_process('unused') }
	blocked.worker.use_stdio_ctl = true
	blocked.worker.stdio_fd[0] = pipe[1]
	assert C.fcntl(pipe[1], C.F_SETFL, C.fcntl(pipe[1], C.F_GETFL) | C.O_NONBLOCK) == 0
	started := time.sys_mono_now()
	mut refused := false
	for _ in 0 .. 10000 {
		if !blocked.send_window_event(appsdk.WindowEvent{ kind: 'click', sequence: 1, id: 'increase' }) { refused = true; break }
	}
	assert refused && time.sys_mono_now() - started < 2_000_000_000
	blocked.window_protocol = 2
	blocked.window_frame = appsdk.WindowFrame{ format: 2, sequence: 1 }
	blocked.window_input_id = 'memo'.clone()
	blocked.window_input = []u8{len: appsdk.window_input_limit, init: `x`}
	blocked.window_input_dirty = true
	blocked.window_key_input('\r')
	assert blocked.window_input_dirty && blocked.window_input.len == appsdk.window_input_limit && blocked.status.contains('kept')
	C.close(pipe[0])
	blocked.window_key_input('\r')
	assert blocked.window_input_dirty && blocked.status.contains('kept')
	assert !blocked.send_window_event(appsdk.WindowEvent{ format: 2, kind: 'close' })
	blocked.retire_worker()
	blocked.close_app()
	println('Software native windows: bounded frames, namespaced controls, ordinary-service launch, clicks, close acknowledgement and EOF retirement passed')
	check_software_window_text()!
}

fn software_text_frame(sequence u64, text string) appsdk.WindowFrame {
	return appsdk.WindowFrame{ format: 2, sequence: sequence, title: 'Memo', width: 320, height: 160, elements: [
		appsdk.WindowElement{ kind: 'input', id: 'software.confirm', text: text, x: 12, y: 12, width: 280, height: 32, color: 0, background: 0xffffff },
		appsdk.WindowElement{ kind: 'button', id: 'save', text: 'Save', x: 12, y: 60, width: 120, height: 32, color: 0, background: 0xe0e0ff }] }
}

fn software_window_text_child() {
	mut text := 'Initial'.clone()
	mut sequence := u64(1)
	for {
		frame := software_text_frame(sequence, text)
		encoded := frame.encode() or { panic(err) }
		println(appsdk.window_prefix + encoded)
		flush_stdout()
		mut event := appsdk.read_window_event_for(2) or { panic(err) }
		assert frame.accepts(event)
		if event.kind == 'close' { event.close(); return }
		assert event.kind == 'text' && event.id == 'software.confirm'
		assert event.text == if sequence == 1 { 'é🚀 $literal; $(command)' } else { '' }
		unsafe { text.free() }
		text = event.text.clone()
		event.close(); sequence++
		unsafe { encoded.free(); (&array(&frame.elements)).free() }
	}
}

fn check_software_window_text() ! {
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192},
		rows: [SoftwareRow{ id: 'memo', installed_version: '1.0.0', installed_kind: 'native', installed_window_protocol: 2 }] }
	app.launch_request = json2.encode(packagecore.Request{ id: 'memo' })
	app.run_requested()
	assert app.window_protocol == 2 && app.worker.args == ['run-window', 'memo']
	wait_window_frame(mut app, 1)!
	app.key_input('unfocused')
	assert app.window_input_id == ''
	tree := app.build(ui2.rect(0, 0, 900, 660))!
	assert tree.children.any(it.id == software_window_input_action + '1.software.confirm')
	assert tree.children.any(it.id == software_window_action + '1.save')
	free_window_tree(tree)
	app.handle('software.confirm')!
	app.handle(software_window_input_action + '0.software.confirm')!
	assert app.window_input_id == ''
	app.handle(software_window_input_action + '1.software.confirm')!
	check_window_empty_paste(mut app)
	app.key_input('\x01')
	app.paste_input('é🚀 $literal; $(command)')
	check_window_empty_paste(mut app)
	assert editor_bytes_text(app.window_input) == 'é🚀 $literal; $(command)'
	app.paste_input('\n')
	app.paste_input('x'.repeat(257))
	assert editor_bytes_text(app.window_input) == 'é🚀 $literal; $(command)' && app.window_input_select_all == false
	app.handle(software_window_action + '1.save')!
	assert app.status.contains('Enter') && app.window_input_dirty
	assert !app.prepare_close() && !app.window_closing
	app.key_input('\r')
	wait_window_frame(mut app, 2)!
	assert app.window_frame.elements[0].text == 'é🚀 $literal; $(command)' && app.window_input_id == ''
	app.handle(software_window_input_action + '1.software.confirm')!
	app.handle(software_window_action + '1.save')!
	assert app.window_input_id == ''
	app.handle(software_window_input_action + '2.software.confirm')!
	app.key_input('\x7f')
	assert editor_bytes_text(app.window_input) == 'é🚀 $literal; $(command'
	app.key_input('\x01'); app.key_input('\x08')
	assert app.window_input.len == 0
	app.key_input('🚀'); app.key_input('\x7f')
	assert app.window_input.len == 0
	app.paste_input('\x1b') // paste must not activate Escape
	assert app.window_input_dirty
	check_window_empty_paste(mut app)
	// Explicit keyboard deletion can still commit an empty protocol-2 value.
	app.key_input('\r'); wait_window_frame(mut app, 3)!
	assert app.window_frame.elements[0].text == '' && !app.window_input_dirty && app.window_input_id == ''
	app.handle(software_window_input_action + '3.software.confirm')!
	check_window_empty_paste(mut app)
	app.key_input('unsent edit')
	app.key_input('\x1b')
	assert app.window_input_id == '' && !app.window_input_dirty
	assert !app.prepare_close() && app.window_closing
	wait_for_software(mut app)
	app.close_app()
	mut parser := SoftwareApp{ window_mode: true, window_protocol: 2 }
	frame := software_text_frame(1, 'old')
	text := frame.encode()!
	parser.window_line(appsdk.window_prefix + text)
	parser.handle_window(software_window_input_action + '1.software.confirm')
	parser.window_paste_input(' draft')
	next := software_text_frame(2, 'new')
	new_text := next.encode()!
	parser.window_line(appsdk.window_prefix + new_text)
	assert parser.window_input_id == '' && parser.status.contains('discarded')
	parser.handle_window(software_window_input_action + '2.software.confirm')
	assert editor_bytes_text(parser.window_input) == 'new'
	legacy := appsdk.WindowFrame{ sequence: 3, title: 'Legacy', width: 64, height: 64 }.encode()!
	parser.window_line(appsdk.window_prefix + legacy)
	assert parser.window_failure.contains('manifest') && parser.window_input_id == '' && parser.window_frame.sequence == 2
	parser.close_app()
	unsafe { text.free(); new_text.free(); legacy.free(); (&array(&frame.elements)).free(); (&array(&next.elements)).free() }
	println('Software native text: focus, UTF-8 bounds, literal replacement, stale controls, explicit commit/discard, close guard and protocol admission passed')
}

fn main() {
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	if os.args.len == 3 && os.args[1] == 'deployment-chooser' { check_software_deployment_chooser(os.args[2]) or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'deployment-chooser-memory' { check_software_deployment_chooser_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'cleanup-memory' { check_software_cleanup_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'audit-memory' { check_software_audit_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'audit-search-memory' { check_software_audit_search_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'snapshot-memory' { check_software_snapshot_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'snapshot-export-memory' { check_software_snapshot_export_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'mirror-navigation-memory' { check_software_mirror_navigation_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'deployment-navigation-memory' { check_software_deployment_navigation_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'repository-navigation-memory' { check_software_repository_navigation_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'package-navigation-memory' { check_software_package_navigation_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'policy-navigation-memory' { check_software_policy_navigation_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'data-navigation-memory' { check_software_data_navigation_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'launch-navigation-memory' { check_software_launch_navigation_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'cleanup-navigation-memory' { check_software_cleanup_navigation_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'verify-navigation-memory' { check_software_verify_navigation_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'admin-memory' { check_software_admin_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'window-memory' { check_window_broker_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'data-memory' { check_software_data_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'policy-memory' { check_software_policy_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'metadata-memory' { check_software_metadata_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'details-memory' { check_software_details_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'view-memory' { check_software_view_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'failure-memory' { check_software_failure_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'repair-memory' { check_software_repair_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'health-memory' { check_software_health_memory() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == 'health-progress-memory' { check_software_health_progress_memory() or { panic(err) }; return }
	mut args := os.args.clone()
	if args.len > 1 && args[1] == '--progress' { args.delete(1) }
	// This same executable is a literal-argv service fixture for asynchronous
	// view/run transitions. It deliberately returns useful launch diagnostics.
	if args.len > 1 {
		if software_verify_navigation_service_fixture(args) or { panic(err) } { return }
		if software_cleanup_navigation_service_fixture(args) or { panic(err) } { return }
		if software_launch_navigation_service_fixture(args) or { panic(err) } { return }
		if software_data_navigation_service_fixture(args) or { panic(err) } { return }
		if software_policy_navigation_service_fixture(args) or { panic(err) } { return }
		if software_package_navigation_service_fixture(args) or { panic(err) } { return }
		if software_repository_navigation_service_fixture(args) or { panic(err) } { return }
		if software_deployment_navigation_service_fixture(args) or { panic(err) } { return }
		if software_audit_search_service_fixture(args) { return }
		if software_mirror_navigation_service_fixture(args) or { panic(err) } { return }
		if software_snapshot_service_fixture(args) { return }
		if software_audit_service_fixture(args) { return }
		if software_cleanup_service_fixture(args) { return }
		if software_health_service_fixture(args) { return }
		if software_failure_service_fixture(args) { return }
		if software_verify_service_fixture(args) { return }
		if software_view_service_fixture(args) { return }
		if software_policy_service_fixture(args) or { panic(err) } { return }
		if software_metadata_service_fixture(args) { return }
		if args[1] == 'admin' {
			exporting := args.len == 7 && args[2..5] == ['--progress', 'mirror-deployment-apply', 'd'.repeat(64)]
			assert exporting || args[2..] in [['--progress', 'apply', 'c'.repeat(64), 'install', 'editor'], ['--progress', 'apply', 'c'.repeat(64), 'repair']]
			mut bytes := [257]u8{}
			mut count := 0
			for count < bytes.len {
				assert C.read(0, &bytes[count], 1) == 1
				if bytes[count] == `\n` { break }
				count++
			}
			assert unsafe { tos(&bytes[0], count) } == 'fixture secret é'
			if exporting {
				assert software_mirror_service_fixture([args[0], ...args[3..]]) or { panic(err) }
				return
			}
			println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
			return
		}
		if args[1] == 'run-window' { software_window_child(args[2]); return }
		if args[1] == 'run-args' {
			assert args[2..] == ['editor', '--data-cwd', '--file', '/private/tmp/a space; $literal.txt', '--', '-i', '/private/tmp/a space; $literal.txt', '', '$(literal)']
			time.sleep(30 * time.millisecond)
			eprintln('fixture: granted file is unavailable to the ordinary account')
			exit(27)
		}
		if software_data_service_fixture(args) or { panic(err) } { return }
		if software_deployment_service_fixture(args) or { panic(err) } { return }
		if software_mirror_service_fixture(args) or { panic(err) } { return }
		if software_repository_service_fixture(args) or { panic(err) } { return }
		if args[1] == 'view' {
			println(json2.encode(SoftwareView{ format: 1, architecture: 'aarch64' }))
			return
		}
		if args[1] == 'run' {
			assert args[2..] == ['editor', '/private/tmp/document with spaces; \$literal.txt']
			eprintln('fixture: ordinary user session required')
			exit(19)
		}
		if args[1] == 'install' && args[2] == 'progress-app' {
			assert os.args[1] == '--progress'
			frame := pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'download',
				package: 'progress-app', repository: 'trusted', path: 'bin/app', current: 128, total: 256 }) + '\n'
			print(frame[..7]); flush_stdout()
			time.sleep(20 * time.millisecond)
			print(frame[7..]); flush_stdout()
			time.sleep(200 * time.millisecond)
			eprintln('fixture: transfer interrupted; retained partial data for retry')
			exit(27)
		}
		if args[1] == 'review' {
			if args.len > 3 && args[3] == 'broken' { eprintln('fixture: dependency unavailable'); exit(17) }
			review := fixture_review(args[2], args[3..])
			println(json2.encode(if args.len > 3 && args[3] == 'wrong-format' {
				pkgprotocol.Review{ ...review, format: 2 }
			} else if args.len > 3 && args[3] == 'wrong-intent' {
				pkgprotocol.Review{ ...review, names: ['other'] }
			} else { review }))
			return
		}
		if args[1] == 'apply' {
			assert args[2..] in [['c'.repeat(64), 'install', 'editor'], ['c'.repeat(64), 'repair']]
			eprintln('fixture: package review is stale; review again')
			exit(23)
		}
		if args[1] == 'lease-hold' { time.sleep(200 * time.millisecond); return }
		panic('unexpected fixture service command')
	}
	mut app := SoftwareApp{ query: []u8{cap: 256}, output: []u8{cap: 8192} }
	view := SoftwareView{
		format:       1
		generation:   1
		architecture: 'aarch64'
		launch_user: 'alex'
		rows:         [
			SoftwareRow{ id: 'editor', name: 'Editor', description: 'Write text documents', kind: 'native', version: '2.0.0', installed_version: '1.0.0', requested: true, updatable: true, update_action: 'update', permissions: ['files'] },
			SoftwareRow{ id: 'browser', name: 'Browser', description: 'Browse websites', kind: 'native', version: '1.0.0' },
			SoftwareRow{ id: 'runtime', name: 'Runtime', description: 'Shared runtime', kind: 'runtime', version: '1.0.0', installed_version: '1.0.0' },
			SoftwareRow{ id: 'blocked', name: 'Blocked', description: 'License required', kind: 'native', version: '1.0.0', diagnostic: 'License acceptance required' },
		].map(SoftwareRow{ ...it, architecture: 'aarch64', repository: 'trusted', public_key: 'a'.repeat(64), license: 'MIT',
			installed_name: if it.installed_version == '' { '' } else { it.name }, installed_kind: if it.installed_version == '' { '' } else { it.kind } })
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
	assert app.review == 'upgrade'
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
	assert tree.children.any(it.id == 'software.run')
	assert tree.children.any(it.id == 'software.run' && it.text == 'Launch as alex')
	assert tree.children.any(it.id == 'software.run-terminal' && it.text == 'Launch in Terminal')
	app.handle('software.run-terminal') or { panic(err) }
	assert app.terminal_app != unsafe { nil } && app.terminal_app.argv == [app.service_path, 'run-terminal', 'editor']
	app.key_input('SELECT 42;\n')
	assert app.terminal_app.input == 'SELECT 42;\n'
	assert !app.prepare_close()
	app.handle('software.terminal-back') or { panic(err) }
	assert app.terminal_app != unsafe { nil }
	app.terminal_app.exited = true
	assert app.prepare_close()
	app.handle('software.terminal-back') or { panic(err) }
	assert app.terminal_app == unsafe { nil }
	wait_for_software(mut app)
	compact := app.build(ui2.rect(0, 0, 480, 300)) or { panic(err) }
	assert compact.children.any(it.id == 'software.reload')
	assert compact.children.any(it.text == app.status) && !compact.children.any(it.id == 'software.confirm')
	assert !compact.children.any(it.id == 'software.install')
	app.worker = os.new_process(os.find_abs_path_of_executable('false') or { panic(err) })
	app.worker.set_args(['owned worker argument'.clone()])
	app.worker.wait()
	assert app.worker.code == 1
	assert !app.prepare_close()
	app.handle('software.run') or { panic(err) }
	assert app.launch_request == ''
	app.retire_worker()
	assert app.prepare_close()
	app.close_app()
	mut launched := SoftwareApp{ service_path: os.executable(), query: []u8{cap: 256}, output: []u8{cap: 8192} }
	launched.start(['view'], true)
	encoded_request := json2.encode(packagecore.Request{ id: 'editor', document: '/private/tmp/document with spaces; \$literal.txt' })
	launched.handle(packagecore.request_prefix + encoded_request) or { panic(err) }
	assert launched.launch_request.len > 0
	for _ in 0 .. 500 {
		launched.poll()
		if launched.worker == unsafe { nil } { break }
		time.sleep(time.millisecond)
	}
	assert launched.worker == unsafe { nil }
	assert launched.launch_request == ''
	assert launched.status.contains('ordinary user session required')
	assert launched.prepare_close()
	launched.launch_request = '{"id":"bad;command"}'.clone()
	launched.run_requested()
	assert launched.worker == unsafe { nil }
	assert launched.launch_request == ''
	assert launched.status.contains('invalid package launch request')
	launched.close_app()
	mut detached := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192} }
	detached.start(['lease-hold'], false)
	detached.worker_run = true
	pid := detached.worker.pid
	assert !detached.prepare_close()
	detached.close_app()
	assert C.kill(pid, 0) == 0, 'forced monitor retirement must retain the service lease holder'
	mut child_status := 0
	assert C.waitpid(pid, &child_status, 0) == pid
	check_package_review()
	check_software_package_navigation() or { panic(err) }
	check_resolved_updates() or { panic(err) }
	check_repository_management() or { panic(err) }
	check_software_repository_navigation() or { panic(err) }
	check_software_progress() or { panic(err) }
	check_software_verify() or { panic(err) }
	check_software_verify_navigation() or { panic(err) }
	check_software_repair() or { panic(err) }
	check_software_health() or { panic(err) }
	check_software_cleanup() or { panic(err) }
	check_software_cleanup_navigation() or { panic(err) }
	check_software_deployment() or { panic(err) }
	check_software_deployment_navigation() or { panic(err) }
	check_software_audit() or { panic(err) }
	check_software_audit_search() or { panic(err) }
	check_software_snapshot() or { panic(err) }
	check_software_snapshot_export() or { panic(err) }
	check_software_mirror_navigation() or { panic(err) }
	check_software_mirror() or { panic(err) }
	check_software_locked_mirror() or { panic(err) }
	check_software_launch_options() or { panic(err) }
	check_software_launch_navigation() or { panic(err) }
	check_software_window() or { panic(err) }
	check_software_admin() or { panic(err) }
	check_software_data() or { panic(err) }
	check_software_data_navigation() or { panic(err) }
	check_software_policy() or { panic(err) }
	check_software_policy_navigation() or { panic(err) }
	check_software_metadata() or { panic(err) }
	check_software_details() or { panic(err) }
	check_software_view_reader() or { panic(err) }
	check_software_failure() or { panic(err) }
	check_software_failure_bounds() or { panic(err) }
	println('Software empty clipboard: policy paths, launch arguments/file grants, administrator passwords and native clean/dirty fields preserve text, focus, selection and state; explicit keyboard editing and empty native commits passed')
	println('Software UI: catalog, package/trust review, literal confirmation, revocation, URL paging, diagnostics and close guard passed')
}

fn admin_tree_has_secret(tree ui2.Element) bool {
	if tree.text.contains('fixture secret') { return true }
	for child in tree.children { if admin_tree_has_secret(child) { return true } }
	return false
}

fn check_software_admin() ! {
	mut app := SoftwareApp{ administration_required: true, service_path: os.executable(), output: []u8{cap: 8192}, query: []u8{cap: 256} }
	app.start(['apply', 'c'.repeat(64), 'install', 'editor'], false)
	assert app.admin_prompt && app.worker.args == ['admin', '--progress', 'apply', 'c'.repeat(64), 'install', 'editor']
	check_admin_empty_paste(mut app)
	app.key_input('fixture secret é')
	check_admin_empty_paste(mut app)
	assert app.admin_password_len == 'fixture secret é'.len
	app.paste_input('\n')
	app.paste_input('x'.repeat(257))
	assert app.admin_password_len == 'fixture secret é'.len && app.admin_prompt
	app.handle('software.confirm')!
	assert app.admin_prompt
	tree := app.build(ui2.rect(0, 0, 900, 660))!
	assert !admin_tree_has_secret(tree)
	free_window_tree(tree)
	app.key_input('\x7f')
	assert app.admin_password_len == 'fixture secret '.len
	app.key_input('é')
	app.handle('software.admin.approve')!
	assert !app.admin_prompt && app.admin_password_len == 0 && app.admin_password.all(it == 0)
	wait_for_software(mut app)
	assert app.worker == unsafe { nil } && app.status.contains('Select an application')
	app.close_app()
	mut cancelled := SoftwareApp{ administration_required: true, service_path: os.executable(), output: []u8{cap: 8192} }
	cancelled.start(['apply', 'c'.repeat(64), 'install', 'editor'], false)
	cancelled.key_input('fixture secret é')
	assert cancelled.prepare_close() && cancelled.worker == unsafe { nil }
	assert cancelled.admin_password.all(it == 0) && !cancelled.admin_prompt
	cancelled.close_app()
	mut refresh := SoftwareApp{ administration_required: true, service_path: '/missing-package-client'.clone(), admin_prompt: true,
		admin_focus: true, repository_worker: .refresh }
	refresh.cancel_admin()
	assert refresh.repository_result.contains('trust was saved') && !refresh.admin_prompt
	refresh.close_app()
	println('Software administrator approval: frozen literal request, masked bounded UTF-8 password, hidden-action refusal, credential wiping, cancellation and progress passed')
}

fn check_admin_empty_paste(mut app SoftwareApp) {
	password := app.admin_password
	length := app.admin_password_len; mask := editor_bytes_text(app.admin_mask); storage := app.admin_mask.data
	status := app.status; focused := app.admin_focus; selected := app.admin_select_all; pid := app.worker.pid
	for focus in [false, true]! {
		for selection in [false, true]! {
			app.admin_focus = focus; app.admin_select_all = selection
			app.paste_input('')
			assert app.admin_password == password && app.admin_password_len == length
			assert editor_bytes_text(app.admin_mask) == mask && app.admin_mask.data == storage
			assert app.admin_prompt && app.admin_focus == focus && app.admin_select_all == selection
			assert app.status == status && app.worker.pid == pid
		}
	}
	app.admin_focus = focused; app.admin_select_all = selected
}

fn check_window_empty_paste(mut app SoftwareApp) {
	text := editor_bytes_text(app.window_input); storage := app.window_input.data
	id := app.window_input_id; dirty := app.window_input_dirty; selected := app.window_input_select_all
	status := app.status; sequence := app.window_frame.sequence; closing := app.window_closing
	for selection in [false, true]! {
		app.window_input_select_all = selection
		app.paste_input('')
		assert editor_bytes_text(app.window_input) == text && app.window_input.data == storage
		assert app.window_input_id == id && app.window_input_dirty == dirty && app.window_input_select_all == selection
		assert app.status == status && app.window_frame.sequence == sequence && app.window_closing == closing
	}
	app.window_input_select_all = selected
}

fn check_software_admin_memory() ! {
	$if !track_heap ? { return error('compile administrator memory fixture with -d track_heap') }
	$if track_heap ? {
		mut pipe := [2]i32{}
		assert C.pipe(&pipe[0]) == 0
		mut app := SoftwareApp{ worker: os.new_process('unused') }
		app.worker.use_stdio_ctl = true; app.worker.stdio_fd[0] = pipe[1]
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.begin_admin_prompt()
				check_admin_empty_paste(mut app)
				app.admin_paste_input('fixture secret é')
				check_admin_empty_paste(mut app)
				free_window_tree(app.build_admin(ui2.rect(0, 0, 900, 660)))
				app.clear_admin_prompt()
				for byte in app.admin_password { assert byte == 0 }
			}
			unsafe { app.status.free() }; app.status = ''
		}
		kept := C.vinix_heap_end()
		C.close(pipe[0]); app.retire_worker(); app.close_app()
		assert kept == 0, 'administrator approval retained ${kept} bytes'
		println('Software administrator approval: 1000 prompt/edit/render/wipe cycles retain zero tracked bytes')
		println('Software empty clipboard: 1000 empty/populated credential focus/selection/render/wipe cycles retain zero tracked bytes')
	}
}

fn check_window_broker_memory() ! {
	$if !track_heap ? { return error('compile this fixture with -d track_heap') }
	$if track_heap ? {
	mut app := SoftwareApp{ window_mode: true, window_protocol: 2, output: []u8{cap: 8192}, window_pending: []u8{cap: appsdk.window_frame_limit + appsdk.window_prefix.len} }
	unsafe { app.output.flags |= .noslices; app.window_pending.flags |= .noslices }
	mut sequence := u64(1)
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			frame := software_text_frame(sequence, 'é🚀')
			text := frame.encode()!
			line := appsdk.window_prefix + text + '\n'
			middle := line.len / 2
			app.window_output(unsafe { tos(line.str, middle) })
			app.window_output(unsafe { tos(line.str + middle, line.len - middle) })
			value := software_window_sequence(sequence)
			action := software_window_input_action + value + 'software.confirm'
			app.handle_window(action)
			check_window_empty_paste(mut app)
			app.window_key_input('\x01')
			app.window_paste_input('draft')
			check_window_empty_paste(mut app)
			free_window_tree(app.build_window(ui2.rect(0, 0, 900, 660)))
			app.window_key_input('\x1b')
			unsafe { text.free(); line.free(); value.free(); action.free(); (&array(&frame.elements)).free() }
			sequence++
		}
		app.window_frame.close()
		unsafe { app.status.free() }
		app.status = ''
	}
	kept := C.vinix_heap_end()
	app.close_app()
	assert kept == 0, 'native window broker retained ${kept} bytes'
	println('Native window broker: 1000 fragmented text frames, focus/edit/discard, UI builds and owned-tree retirements retain zero tracked bytes')
	}
}

const mirror_fixture_destination = '/private/tmp/offline export; $literal'
const mirror_fixture_lock = '/etc/company/approved apps; $literal.json'

fn software_mirror_service_fixture(args []string) !bool {
	if args[1] == 'mirror-deployment-review' {
		assert args.len == 4
		if args[3] == '/missing-lock' { eprintln('fixture: deployment lock is unreadable'); exit(18) }
		if args[3] == '/root-only-lock' { eprintln('fixture: offline deployment export requires a nonempty format-2 lock'); exit(18) }
		base := fixture_review('mirror', ['editor'])
		review := pkgprotocol.Review{ ...base, generation: 0, fingerprint: 'd'.repeat(64),
			rows: base.rows.map(pkgprotocol.ReviewPackage{ ...it, version: '1.0.0', installed_version: '', action: 'export' }) }
		mirror := pkgprotocol.MirrorReview{ format: 1, input_destination: if args[3] == '/wrong-destination' { '/other' } else { args[2] },
			destination: args[2], review: review, cache_needed: 1024, cache_available: 65536, shared_disk: true }
		if args[3] == '/catalog-response' { println(json2.encode(mirror)); return true }
		text := json2.encode(pkgprotocol.DeploymentMirrorReview{ format: 1,
			deployment: if args[3] == '/wrong-source' { '/other.json' } else { args[3] },
			deployment_sha256: if args[3] == '/invalid-digest' { 'invalid' }
				else if args[3] == software_snapshot_fixture_path { 'd'.repeat(64) } else { 'e'.repeat(64) }, mirror: mirror })
		println(if args[3] == '/missing-digest' { text.replace('"deployment_sha256":"' + 'e'.repeat(64) + '",', '') } else { text })
		return true
	}
	if args[1] == 'mirror-deployment-apply' {
		assert os.args[1] == '--progress' || (os.args[1] == 'admin' && os.args[2] == '--progress')
		assert args.len == 5 && args[2] == 'd'.repeat(64) && args[3] == mirror_fixture_destination
		if args[4] == '/changed-lock' { eprintln('fixture: offline mirror review is stale; review again'); exit(23) }
		assert args[4] == mirror_fixture_lock || args[4].len > 200
		os.write_file(os.getenv('VINIX_SOFTWARE_MIRROR_FIXTURE'), json2.encode(args[2..]))!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'copy', package: 'runtime', repository: 'runtime-publisher', path: 'bin/app', current: 4096, total: 4096 }))
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		println('Offline deployment mirror ready: ' + args[3] + '/_deployment.json')
		return true
	}
	if args[1] == 'mirror-review' {
		assert args.len >= 4
		if args[2] == '/missing' { eprintln('fixture: signed payload is unavailable'); exit(18) }
		base := fixture_review('mirror', args[3..])
		review := pkgprotocol.Review{ ...base, generation: 0, rows: base.rows.map(pkgprotocol.ReviewPackage{ ...it, action: 'export' }) }
		println(json2.encode(pkgprotocol.MirrorReview{ format: 1,
			input_destination: if args[2] == '/wrong-intent' { '/other' } else { args[2] },
			destination: args[2], review: review, cache_needed: 1024, cache_available: 65536, shared_disk: true }))
		return true
	}
	if args[1] == 'mirror-apply' {
		assert os.args[1] == '--progress'
		assert args.len == 5 && args[2] == 'c'.repeat(64) && args[4] == 'editor'
		if args[3] == '/stale' { eprintln('fixture: offline mirror review is stale; review again'); exit(23) }
		assert args[3] == mirror_fixture_destination || args[3].len > 200
		os.write_file(os.getenv('VINIX_SOFTWARE_MIRROR_FIXTURE'), json2.encode(args[2..]))!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'copy', package: 'editor', repository: 'trusted', path: 'bin/app', current: 4096, total: 4096 }))
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		println('Offline mirror ready: ' + args[3])
		return true
	}
	return false
}

fn check_software_mirror() ! {
	receipt := os.temp_dir() + '/vinix-software-mirror-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_MIRROR_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_MIRROR_FIXTURE') }
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192},
		rows: [SoftwareRow{ id: 'editor', name: 'Editor', requested: true, installed_version: '1.0.0' }], selected: 0 }
	defer { app.close_app() }
	app.handle('software.mirror')!
	assert app.mirror_mode && !app.deployment_mode && !app.repository_mode
	assert app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.id == 'software.mirror.review')
	app.handle('software.mirror.path')!
	app.paste_input('relative')
	app.handle('software.mirror.review')!
	assert app.worker == unsafe { nil } && app.status.contains('absolute')
	app.key_input('\x01')
	app.paste_input(mirror_fixture_destination)
	app.key_input('\x01')
	app.paste_input('/' + 'x'.repeat(4096))
	assert editor_bytes_text(app.mirror_path) == mirror_fixture_destination
	app.paste_input('/bad\npath')
	assert editor_bytes_text(app.mirror_path) == mirror_fixture_destination
	app.handle('software.mirror.review')!
	assert app.worker_review && app.prepare_close()
	app.handle('software.confirm')!
	assert !os.exists(receipt)
	wait_for_software(mut app)
	assert app.review_ready && app.mirror_details && app.mirror_snapshot.destination == mirror_fixture_destination
	assert app.review_snapshot.rows.len == 2 && app.review_snapshot.rows.all(it.action == 'export')
	assert !app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.id == 'software.confirm')
	app.handle('software.mirror.packages')!
	app.handle('software.row.1')!
	tree := app.build(ui2.rect(0, 0, 900, 660))!
	assert tree.children.any(it.id == 'software.confirm')
	assert tree.children.any(it.text.contains('runtime-publisher'))
	assert tree.children.any(it.text.contains('Vendor-EULA (proprietary)') && it.text.contains('firmware'))
	assert tree.children.any(it.text.contains('Permissions: network, process'))
	app.selected = -1
	software_repository_text(mut app.mirror_path, '/other')
	app.handle('software.confirm')!
	assert app.worker_mirror && !app.prepare_close()
	wait_for_software(mut app)
	assert app.mirror_mode && app.status.contains('Offline mirror ready') && app.progress_seen
	assert json2.decode[[]string](os.read_file(receipt)!)! == ['c'.repeat(64), mirror_fixture_destination, 'editor']
	os.rm(receipt)!
	app.handle('software.mirror.scope')!
	assert app.mirror_all
	for path in ['/missing', '/wrong-intent', '/stale', '/media/' + 'long-path-'.repeat(35)] {
		software_repository_text(mut app.mirror_path, path)
		app.handle('software.mirror.review')!
		wait_for_software(mut app)
		if path == '/missing' {
			assert !app.review_ready && app.status.contains('unavailable')
		} else if path == '/wrong-intent' {
			assert !app.review_ready && app.mirror_pending == ''
		} else {
			assert app.review_ready && app.mirror_details
			if path.len > 200 {
				assert app.mirror_pages.len > 1
				app.handle('software.mirror.packages')!
				assert app.mirror_details
				for app.mirror_seen + 1 < app.mirror_pages.len { app.handle('software.mirror.next')! }
			}
			app.handle('software.mirror.packages')!
			app.handle('software.confirm')!
			wait_for_software(mut app)
			if path == '/stale' { assert app.status.contains('stale') && !os.exists(receipt) }
		}
	}
	app.handle('software.mirror.review')!
	wait_for_software(mut app)
	app.handle('software.cancel')!
	assert app.review_snapshot.rows.len == 0 && app.mirror_pages.len == 0 && app.mirror_snapshot.destination == ''
	app.handle('software.mirror.back')!
	assert !app.mirror_mode
	mut malformed := SoftwareApp{ mirror_pages: []string{cap: 128} }
	bytes := '\x80'.repeat(160)
	malformed.mirror_path_parts(bytes)
	assert malformed.mirror_pages.len == 2
	joined := malformed.mirror_pages.join('')
	assert joined == bytes
	unsafe { bytes.free(); joined.free() }
	malformed.close_app()
	println('Software offline export: destination paging, dependency provenance, literal confirmation, installed scope, progress, stale diagnostics and close guard passed')
}

fn check_software_locked_mirror() ! {
	receipt := os.temp_dir() + '/vinix-software-locked-mirror-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_MIRROR_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_MIRROR_FIXTURE') }
	// Organization locks work even when this machine has no catalog selection
	// or installed roots. The reviewed document supplies the package intent.
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, selected: -1 }
	defer { app.close_app() }
	app.handle('software.mirror')!
	software_repository_text(mut app.mirror_path, mirror_fixture_destination)
	app.handle('software.mirror.scope')!
	assert app.mirror_all && !app.mirror_locked
	app.handle('software.mirror.scope')!
	assert app.mirror_locked && !app.mirror_all
	assert app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.id == 'software.mirror.lock')
	app.handle('software.mirror.review')!
	assert app.worker == unsafe { nil } && app.status.contains('absolute organization')
	app.handle('software.mirror.lock')!
	app.paste_input('relative')
	app.handle('software.mirror.review')!
	assert app.worker == unsafe { nil }
	app.key_input('\x01')
	app.paste_input(mirror_fixture_lock)
	app.key_input('\x01')
	for invalid in ['/bad\npath', '/bad\x80', '/' + 'x'.repeat(4096)] {
		app.paste_input(invalid)
		assert editor_bytes_text(app.mirror_lock_path) == mirror_fixture_lock
	}
	assert editor_bytes_text(app.mirror_path) == mirror_fixture_destination
	for source in [mirror_fixture_lock, '/media/' + 'approved-'.repeat(35), '/wrong-source', '/wrong-destination',
		'/invalid-digest', '/missing-digest', '/catalog-response', '/missing-lock', '/root-only-lock', '/changed-lock'] {
		software_repository_text(mut app.mirror_lock_path, source)
		app.handle('software.mirror.review')!
		assert app.worker_review && app.prepare_close()
		app.handle('software.mirror.scope')! // blocked while resolving
		app.handle('software.confirm')!
		assert !os.exists(receipt)
		wait_for_software(mut app)
		if source.starts_with('/wrong-') || source in ['/invalid-digest', '/missing-digest', '/catalog-response', '/missing-lock', '/root-only-lock'] {
			assert !app.review_ready && app.mirror_lock_pending == '' && app.mirror_lock_sha256 == ''
			assert app.mirror_pages.len == 0 && app.mirror_snapshot.destination == ''
			continue
		}
		assert app.review_ready && app.mirror_locked && app.mirror_details
		assert app.mirror_lock_pending == source && app.mirror_lock_sha256 == 'e'.repeat(64)
		assert app.review_names == ['editor'] && app.review_snapshot.rows.all(it.version == '1.0.0')
		assert app.mirror_page_labels.last().contains('SHA-256')
		assert app.mirror_pages.last() == 'e'.repeat(64)
		app.handle('software.mirror.packages')!
		assert app.mirror_details // source path and digest must also be visited
		app.handle('software.confirm')!
		assert !os.exists(receipt)
		mut source_parts := ''
		for i, part in app.mirror_pages {
			if app.mirror_page_labels[i].contains('source path') { source_parts += part }
		}
		assert source_parts == source
		for app.mirror_seen + 1 < app.mirror_pages.len { app.handle('software.mirror.next')! }
		assert app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.text == 'e'.repeat(64))
		app.handle('software.mirror.packages')!
		app.handle('software.row.1')!
		tree := app.build(ui2.rect(0, 0, 900, 660))!
		assert tree.children.any(it.text.contains('runtime-publisher'))
		assert tree.children.any(it.text.contains('Vendor-EULA (proprietary)') && it.text.contains('firmware'))
		assert tree.children.any(it.text.contains('Permissions: network, process'))
		app.handle('software.mirror.details')!
		assert app.mirror_details
		app.handle('software.mirror.packages')!
		// Form storage is no longer authoritative once the review is accepted.
		software_repository_text(mut app.mirror_path, '/other')
		software_repository_text(mut app.mirror_lock_path, '/other-lock')
		app.handle('software.confirm')!
		assert app.worker_mirror && !app.prepare_close() && app.mirror_lock_pending == ''
		wait_for_software(mut app)
		if source == '/changed-lock' { assert app.status.contains('stale') && !os.exists(receipt) }
		else {
			assert app.progress_seen && app.status.contains('/_deployment.json')
			assert json2.decode[[]string](os.read_file(receipt)!)! == ['d'.repeat(64), mirror_fixture_destination, source]
			os.rm(receipt)!
		}
		software_repository_text(mut app.mirror_path, mirror_fixture_destination)
	}
	software_repository_text(mut app.mirror_lock_path, mirror_fixture_lock)
	app.handle('software.mirror.review')!
	wait_for_software(mut app)
	app.handle('software.cancel')!
	assert app.review_names.len == 0 && app.mirror_lock_pending == '' && app.mirror_lock_sha256 == ''
	assert app.mirror_page_labels.len == 0 && app.mirror_pages.len == 0
	app.handle('software.mirror.scope')!
	assert !app.mirror_locked && !app.mirror_all
	assert !app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.id == 'software.mirror.lock')
	println('Software locked offline export: exact older runtime, source/digest paging, literal frozen confirmation, invalid responses, stale diagnostics, progress and cancellation passed')
}

fn check_software_launch_options() ! {
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: []u8{cap: 256},
		rows: [SoftwareRow{ id: 'editor', name: 'Editor', kind: 'linux', installed_version: '1.0.0', permissions: ['files'] }], selected: 0 }
	app.handle('software.run-options')!
	assert app.launch_mode && app.launch_id == 'editor' && app.launch_data_cwd
	app.handle('software.launch.arguments')!
	app.paste_input('-i "/private/tmp/a space; $literal.txt" "" $(literal)')
	app.handle('software.launch.file')!
	app.paste_input('/private/tmp/a space; $literal.txt')
	app.handle('software.launch.add-file')!
	assert app.launch_documents == ['/private/tmp/a space; $literal.txt'] && app.launch_file.len == 0
	view := app.build(ui2.rect(0, 0, 900, 660))!
	assert view.children.any(it.id == 'software.launch.run') && view.children.any(it.id == 'software.launch.terminal')
	app.handle('software.launch.run')!
	assert app.worker != unsafe { nil } && app.worker_run
	assert !app.prepare_close()
	app.handle('software.launch.back')!
	app.handle('software.launch.arguments')!
	app.paste_input('changed')
	assert app.launch_mode && editor_bytes_text(app.launch_arguments).starts_with('-i ')
	wait_for_software(mut app)
	assert app.status.contains('ordinary account') && app.worker == unsafe { nil }
	assert app.launch_documents == ['/private/tmp/a space; $literal.txt']
	app.handle('software.launch.terminal')!
	assert !app.launch_mode && app.terminal_app != unsafe { nil }
	assert app.terminal_app.argv == [app.service_path, 'run-terminal-args', 'editor', '--data-cwd', '--file', '/private/tmp/a space; $literal.txt', '--', '-i', '/private/tmp/a space; $literal.txt', '', '$(literal)']
	app.terminal_app.exited = true
	app.handle('software.terminal-back')!
	wait_for_software(mut app)
	app.close_app()
	println('Software launch options: quoted literal arguments, separate file grants, frozen worker input, diagnostics and terminal transfer passed')
}

const deployment_fixture_path = '/private/tmp/deployment with spaces; \$literal.json'

fn software_deployment_service_fixture(args []string) !bool {
	if args[1] == 'deployment-review' {
		assert args.len == 3
		path := args[2]
		if path == '/missing.json' { eprintln('fixture: deployment file unavailable'); exit(18) }
		review := fixture_review('deploy', ['editor'])
		println(json2.encode(if path == '/wrong-format.json' {
			pkgprotocol.Review{ ...review, format: 2 }
		} else if path == '/wrong-operation.json' {
			pkgprotocol.Review{ ...review, operation: 'upgrade', names: [] }
		} else if path == '/empty.json' {
			pkgprotocol.Review{ ...review, names: [], requested: [], rows: [
				pkgprotocol.ReviewPackage{ ...review.rows[0], requested: false, action: 'remove' },
				pkgprotocol.ReviewPackage{ ...review.rows[1], action: 'remove' },
			] }
		} else { review }))
		return true
	}
	if args[1] == 'deployment-apply' {
		assert os.args[1] == '--progress', 'deployment transactions request live progress'
		assert args.len == 4 && args[2] == 'c'.repeat(64)
		if args[3] == '/stale.json' { eprintln('fixture: deployment review is stale; review again'); exit(23) }
		assert args[3] in [deployment_fixture_path, '/empty.json']
		os.write_file(os.getenv('VINIX_SOFTWARE_DEPLOYMENT_FIXTURE'), json2.encode(args[2..]))!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete' }))
		return true
	}
	return false
}

fn check_software_deployment() ! {
	receipt := os.temp_dir() + '/vinix-software-deployment-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_DEPLOYMENT_FIXTURE', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_DEPLOYMENT_FIXTURE') }
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: []u8{cap: 256} }
	defer { app.close_app() }
	app.handle('software.deployment')!
	assert app.deployment_mode && app.worker == unsafe { nil }
	form := app.build(ui2.rect(0, 0, 640, 610))!
	assert form.children.any(it.id == 'software.deployment.review')
	assert form.children.any(it.text.contains('Empty deployments remove all packages'))
	app.handle('software.deployment.path')!
	app.paste_input('relative.json')
	app.handle('software.deployment.review')!
	assert app.worker == unsafe { nil } && app.status.contains('absolute')
	app.key_input('\x01')
	app.paste_input(deployment_fixture_path)
	app.key_input('\x01')
	app.paste_input('/' + 'x'.repeat(4096))
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path
	app.paste_input('/two\nlines.json')
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path
	app.paste_input('/invalid\xff.json')
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path
	app.paste_input('/control\xc2\x85.json')
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path
	app.paste_input('/部署/пакеты.json')
	assert editor_bytes_text(app.deployment_path) == '/部署/пакеты.json'
	app.key_input('\x01')
	app.paste_input(deployment_fixture_path)
	app.handle('software.deployment.review')!
	assert app.worker_review && !app.review_ready && app.prepare_close()
	app.handle('software.confirm')!
	assert !os.exists(receipt)
	wait_for_software(mut app)
	assert app.review_ready && app.review_snapshot.names == ['editor']
	assert app.review_snapshot.rows.len == 2 && app.status.contains(deployment_fixture_path)
	app.handle('software.row.1')!
	tree := app.build(ui2.rect(0, 0, 900, 660))!
	assert tree.children.any(it.text.contains('Permissions: network, process'))
	assert tree.children.any(it.text.contains('Vendor-EULA (proprietary)'))
	assert tree.children.any(it.id == 'software.confirm')
	// A form edit cannot alter the reviewed literal argv. Normal typing is frozen.
	app.focus = true
	app.paste_input('/other.json')
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path
	software_repository_text(mut app.deployment_path, '/other.json')
	app.handle('software.confirm')!
	assert !app.prepare_close() && app.deployment_pending == ''
	wait_for_software(mut app)
	assert json2.decode[[]string](os.read_file(receipt)!)! == ['c'.repeat(64), deployment_fixture_path]
	assert !app.deployment_mode && app.review == ''
	os.rm(receipt)!
	for path in ['/missing.json', '/wrong-format.json', '/wrong-operation.json', '/stale.json', '/empty.json'] {
		app.handle('software.deployment')!
		software_repository_text(mut app.deployment_path, path)
		app.handle('software.deployment.review')!
		wait_for_software(mut app)
		if path == '/missing.json' {
			assert !app.review_ready && app.status.contains('unavailable')
		} else if path == '/wrong-format.json' || path == '/wrong-operation.json' {
			assert !app.review_ready && app.review == '' && app.deployment_pending == ''
		} else if path == '/stale.json' {
			assert app.review_ready
			app.handle('software.confirm')!
			wait_for_software(mut app)
			assert app.deployment_mode && !app.review_ready && app.status.contains('stale')
		} else {
			assert app.review_ready && app.review_snapshot.requested.len == 0
			assert app.review_snapshot.rows.all(it.action == 'remove')
			app.handle('software.cancel')!
			assert !os.exists(receipt) && app.deployment_mode && app.deployment_pending == ''
			app.handle('software.deployment.review')!
			wait_for_software(mut app)
			app.handle('software.confirm')!
			wait_for_software(mut app)
			assert json2.decode[[]string](os.read_file(receipt)!)![1] == '/empty.json'
			os.rm(receipt)!
		}
		assert !os.exists(receipt)
	}
	app.handle('software.deployment')!
	app.handle('software.deployment.back')!
	assert !app.deployment_mode && app.worker == unsafe { nil }
	println('Software deployment: full closure, frozen literal path, empty removal, cancellation, bounds, stale/error diagnostics and close guard passed')
}

fn check_software_progress() ! {
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: []u8{cap: 256} }
	defer { app.close_app() }
	app.operation_output('\n\n')
	frame := pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'download',
		package: 'app', path: 'bin/app', current: 64, total: 128 }) + '\n'
	for byte in frame {
		value := byte.ascii_str()
		app.operation_output(value)
		unsafe { value.free() }
	}
	assert app.progress_seen && app.progress_snapshot.current == 64 && app.output.len == 0
	assert app.status.contains('64 / 128 bytes')
	tree := app.build(ui2.rect(0, 0, 900, 660))!
	bar := tree.children.filter(it.id == 'software.progress')[0]
	assert bar.accessibility_role == 'progressbar' && bar.children[0].frame.width == 436
	app.operation_output(pkgprotocol.progress_prefix + '{"format":2}\n')
	assert app.progress_snapshot.current == 64
	app.operation_output('x'.repeat(pkgprotocol.progress_limit + 32) + '\n')
	assert app.progress_pending.len == 0 && !app.progress_skip
	app.operation_output('checksum mismatch; retry from trusted repository')
	app.finish_operation_output()
	assert app.status.contains('checksum mismatch') && !app.status.contains(pkgprotocol.progress_prefix)
	// The real worker emits a fragmented frame before exiting with a diagnostic.
	app.start(['install', 'progress-app'], false)
	assert !app.prepare_close()
	for _ in 0 .. 500 {
		app.poll()
		if app.progress_seen { break }
		time.sleep(time.millisecond)
	}
	assert app.worker != unsafe { nil } && app.progress_snapshot.current == 128
	wait_for_software(mut app)
	assert app.status.contains('transfer interrupted') && app.status.contains('partial data')
	assert !app.status.contains(pkgprotocol.progress_prefix) && app.progress_snapshot.phase != 'complete'
	assert app.prepare_close()
	app.start(['view'], true)
	assert !app.progress_seen && app.progress_snapshot.phase == ''
	wait_for_software(mut app)
	println('Software progress: fragmented frames, bounded buffers, phase bar, diagnostics and worker retirement passed')
}

const repository_fixture_url = 'file:///private/tmp/repository with spaces; $literal'

fn repository_fixture_status() !pkgprotocol.RepositoryStatus {
	path := os.getenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE')
	if path != '' && os.exists(path) { return json2.decode[pkgprotocol.RepositoryStatus](os.read_file(path)!)! }
	return pkgprotocol.RepositoryStatus{ format: 1, architecture: 'aarch64',
		repositories: [pkgprotocol.Repository{ id: 'fixture', url: repository_fixture_url, public_key: 'a'.repeat(64) }],
		history: [pkgprotocol.RepositoryFloor{ id: 'fixture', public_key: 'a'.repeat(64), sequence: 7, index_sha256: 'c'.repeat(64) }] }
}

fn repository_fixture_review(operation string, id string, url string, key string) !pkgprotocol.RepositoryReview {
	status := repository_fixture_status()!
	previous := status.repositories.filter(it.id == id)
	old_url := if previous.len == 0 { '' } else { previous[0].url }
	old_key := if previous.len == 0 { '' } else { previous[0].public_key }
	return pkgprotocol.RepositoryReview{ format: 1, architecture: 'aarch64', operation: operation, id: id,
		url: if operation == 'enroll' { url } else { old_url },
		public_key: if operation == 'enroll' { key } else { old_key }, previous_url: old_url, previous_public_key: old_key,
		fingerprint: if id == 'stale' { 'e'.repeat(64) } else { 'd'.repeat(64) },
		index_sha256: if operation == 'enroll' { 'c'.repeat(64) } else { '' },
		sequence: if operation == 'enroll' { u64(7) } else { u64(0) },
		expires: if operation == 'enroll' { i64(2000000000) } else { i64(0) },
		package_count: if operation == 'enroll' { 3 } else { 0 } }
}

fn software_repository_service_fixture(args []string) !bool {
	if args[1] == '--json' {
		assert args[2..] == ['repo-config']
		status := repository_fixture_status()!
		println(json2.encode(pkgprotocol.RepositoryConfiguration{ format: 1, scope: 'configuration',
			architecture: status.architecture, repositories: status.repositories }))
		return true
	}
	if args[1] == 'repo-review' {
		operation := args[2]
		id := args[3]
		if operation == 'enroll' && os.getenv('VINIX_SOFTWARE_REPOSITORY_BROKEN') == '1' {
			eprintln('fixture: damaged replay history blocks enrollment; restore trusted metadata'); exit(34)
		}
		if id == 'bad-signature' { eprintln('fixture: repository signature verification failed'); exit(31) }
		review := repository_fixture_review(operation, id,
			if operation == 'enroll' { args[4] } else { '' },
			if operation == 'enroll' { args[5] } else { '' })!
		println(json2.encode(if id == 'wrong-format' {
			pkgprotocol.RepositoryReview{ ...review, format: 2 }
		} else if id == 'wrong-intent' { pkgprotocol.RepositoryReview{ ...review, id: 'other' } } else { review }))
		return true
	}
	if args[1] == 'repo-apply' {
		if args[2] == 'e'.repeat(64) { eprintln('fixture: repository review is stale; review again'); exit(32) }
		assert args[2] == 'd'.repeat(64)
		path := os.getenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE')
		assert path != ''
		current := repository_fixture_status()!
		operation := args[3]
		id := args[4]
		assert id == 'fixture'
		if operation == 'enroll' {
			assert args.len == 7 && args[5].starts_with(repository_fixture_url)
			assert args[6] == 'b'.repeat(64)
			next := pkgprotocol.RepositoryStatus{ ...current, repositories: [pkgprotocol.Repository{ id: id, url: args[5], public_key: args[6] }] }
			os.write_file(path, json2.encode(next))!
		} else {
			assert operation == 'revoke' && args.len == 5
			os.write_file(path, json2.encode(pkgprotocol.RepositoryStatus{ ...current, repositories: [] }))!
		}
		println('fixture: repository trust change saved')
		return true
	}
	if args[1] == 'update' {
		if repository_fixture_status()!.repositories.any(it.url.contains('refresh-fails')) {
			eprintln('fixture: catalog refresh failed: publisher unreachable')
			exit(33)
		}
		println('fixture: catalogs refreshed')
		return true
	}
	return false
}

fn check_repository_management() ! {
	path := os.temp_dir() + '/vinix-software-repositories-' + os.getpid().str()
	previous := os.getenv_opt('VINIX_SOFTWARE_REPOSITORY_FIXTURE')
	os.setenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE', path, true)
	defer {
		os.rm(path) or {}
		if value := previous { os.setenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE', value, true) } else { os.unsetenv('VINIX_SOFTWARE_REPOSITORY_FIXTURE') }
	}
	mut app := SoftwareApp{ service_path: os.executable(), query: []u8{cap: 256}, output: []u8{cap: 8192} }
	app.handle('software.repositories')!
	assert app.worker_view && app.prepare_close()
	wait_for_software(mut app)
	assert app.repository_mode && app.repository_status.repositories.len == 1
	app.handle('software.row.0')!
	assert editor_bytes_text(app.repository_id) == 'fixture'
	assert editor_bytes_text(app.repository_url) == repository_fixture_url
	app.handle('software.repository.key')!
	app.key_input('\x01')
	app.paste_input('b'.repeat(64))
	app.paste_input('0')
	assert editor_bytes_text(app.repository_key) == 'b'.repeat(64) && app.status.contains('not truncated')
	app.key_input('\t')
	assert app.repository_focus == 1
	app.key_input('\x1b[Z')
	assert app.repository_focus == 3
	app.handle('software.repository.enroll')!
	assert app.worker_review && !app.repository_review_ready
	app.handle('software.repository.confirm')!
	assert app.worker_review
	wait_for_software(mut app)
	assert app.repository_review_ready && app.repository_review.public_key == 'b'.repeat(64)
	tree := app.build(ui2.rect(0, 0, 900, 660))!
	assert tree.children.any(it.id == 'software.repository.confirm')
	assert tree.children.any(it.text.contains('Previous key:') && it.text.contains('a'.repeat(64)))
	assert tree.children.any(it.text.contains('3 signed catalog entries'))
	assert !os.exists(path), 'review changed repository trust'
	// Confirmation uses the reviewed intent despite unrelated form-buffer edits.
	software_repository_text(mut app.repository_id, 'other')
	app.handle('software.repository.confirm')!
	assert !app.prepare_close()
	wait_for_software(mut app)
	assert repository_fixture_status()!.repositories[0].id == 'fixture'
	assert app.status.contains('trusted') && app.status.contains('refreshed')
	app.handle('software.row.0')!
	app.handle('software.repository.revoke')!
	wait_for_software(mut app)
	assert app.repository_review_ready && app.repository_review.operation == 'revoke'
	app.handle('software.repository.cancel')!
	assert repository_fixture_status()!.repositories.len == 1
	app.handle('software.repository.revoke')!
	wait_for_software(mut app)
	app.handle('software.repository.confirm')!
	wait_for_software(mut app)
	assert app.repository_status.repositories.len == 0 && app.status.contains('revoked')
	assert repository_fixture_status()!.history.len == 1
	// Configuration listing stays reachable while the service refuses damaged
	// maintenance metadata. Enrollment remains blocked; revocation is reviewed.
	os.write_file(path, json2.encode(pkgprotocol.RepositoryStatus{ ...repository_fixture_status()!, repositories: [
		pkgprotocol.Repository{ id: 'fixture', url: repository_fixture_url, public_key: 'a'.repeat(64) }] }))!
	os.setenv('VINIX_SOFTWARE_REPOSITORY_BROKEN', '1', true)
	app.read_repositories(); wait_for_software(mut app)
	assert app.repository_status.scope == 'configuration' && app.repository_status.repositories.len == 1
	app.handle('software.row.0')!
	app.begin_repository_review('enroll'); wait_for_software(mut app)
	assert !app.repository_review_ready && app.status.contains('damaged replay history')
	app.handle('software.repository.revoke')!; wait_for_software(mut app)
	assert app.repository_review_ready && app.repository_review.operation == 'revoke'
	app.handle('software.repository.confirm')!; wait_for_software(mut app)
	assert app.repository_status.repositories.len == 0 && app.status.contains('revoked')
	assert repository_fixture_status()!.history.len == 1
	os.unsetenv('VINIX_SOFTWARE_REPOSITORY_BROKEN')
	println('Software configured repositories: damaged metadata does not block reviewed revocation; enrollment remains refused PASS')
	// Invalid input, invalid response and changed intent never enable confirmation.
	for id in ['bad-signature', 'wrong-format', 'wrong-intent', 'stale'] {
		software_repository_text(mut app.repository_id, id)
		app.begin_repository_review('enroll')
		wait_for_software(mut app)
		if id == 'stale' {
			assert app.repository_review_ready
			app.handle('software.repository.confirm')!
			wait_for_software(mut app)
			assert app.status.contains('stale')
		} else {
			assert !app.repository_review_ready && app.repository_operation == ''
		}
		assert repository_fixture_status()!.repositories.len == 0
	}
	software_repository_text(mut app.repository_key, 'not a key')
	app.begin_repository_review('enroll')
	assert app.worker == unsafe { nil } && app.status.contains('publisher key')
	software_repository_text(mut app.repository_id, 'fixture')
	software_repository_text(mut app.repository_key, 'b'.repeat(64))
	software_repository_text(mut app.repository_url, repository_fixture_url + '/' + 'long-source-'.repeat(30) + '/refresh-fails')
	app.begin_repository_review('enroll')
	wait_for_software(mut app)
	assert app.repository_url_pages.len > 1
	assert !app.build(ui2.rect(0, 0, 640, 610))!.children.any(it.id == 'software.repository.confirm')
	app.handle('software.repository.confirm')!
	assert app.worker == unsafe { nil }
	for app.repository_url_page + 1 < app.repository_url_pages.len { app.handle('software.repository.url-next')! }
	app.handle('software.repository.confirm')!
	wait_for_software(mut app)
	assert app.repository_status.repositories.len == 1
	assert app.status.contains('trust was saved') && app.status.contains('refresh failed')
	app.handle('software.repository.back')!
	wait_for_software(mut app)
	assert !app.repository_mode
	app.close_app()
}

fn check_resolved_updates() ! {
	mut app := SoftwareApp{ service_path: os.executable(), query: []u8{cap: 256}, output: []u8{cap: 8192} }
	view := SoftwareView{ format: 1, generation: 1, architecture: 'aarch64', rows: [
		SoftwareRow{ id: 'editor', name: 'Editor', kind: 'linux', runtime: 'runtime', version: '1.0.0', installed_version: '1.0.0', requested: true },
		SoftwareRow{ id: 'runtime', name: 'Explicit runtime', kind: 'runtime', version: '2.0.0', installed_version: '1.0.0', updatable: true, update_action: 'update' },
		SoftwareRow{ id: 'new-data', name: 'New data', kind: 'data', version: '1.0.0', updatable: true, update_action: 'install' },
		SoftwareRow{ id: 'old-data', name: 'Retired data', kind: 'data', version: '1.0.0', installed_version: '1.0.0', updatable: true, update_action: 'remove' },
		SoftwareRow{ id: 'unchanged-data', name: 'Retained dependency', kind: 'data', version: '1.0.0', installed_version: '1.0.0' },
	].map(SoftwareRow{ ...it, architecture: if it.kind == 'data' { 'all' } else { 'aarch64' }, repository: 'trusted', public_key: 'a'.repeat(64), license: 'MIT',
		installed_name: if it.installed_version == '' { '' } else { it.name }, installed_kind: if it.installed_version == '' { '' } else { it.kind } }) }
	app.output << json2.encode(view).bytes()
	app.load_view()
	app.handle('software.updates')!
	assert app.matching == [1, 2, 3]
	for slot in 0 .. 3 {
		app.handle(software_row_actions[slot])!
		tree := app.build(ui2.rect(0, 0, 900, 660))!
		assert tree.children.any(it.id == 'software.install' && it.text == 'Review updates')
		assert !tree.children.any(it.id == 'software.run')
		if slot == 2 { assert tree.children.any(it.text.contains('Removed by Update all')) }
		app.handle('software.install')!
		assert app.worker_review && app.review == 'upgrade' && app.review_names.len == 0
		wait_for_software(mut app)
		assert app.review_ready && app.review_snapshot.operation == 'upgrade'
		app.handle('software.cancel')!
	}
	// Repairing an implicit dependency must not silently turn it into a root.
	app.selected = 4
	assert !app.build(ui2.rect(0, 0, 900, 660))!.children.any(it.id == 'software.install')
	app.handle('software.install')!
	assert app.review == '' && app.status.contains('complete application set')
	// A failed full plan is visible on reload and when selecting Updates.
	app.output.clear()
	app.output << json2.encode(SoftwareView{ ...view, update_error: 'runtime: permissions blocked by organization policy',
		rows: view.rows.map(SoftwareRow{ ...it, updatable: false, update_action: '' }) }).bytes()
	app.load_view()
	assert app.status.contains('Updates unavailable') && app.status.contains('permissions blocked')
	app.handle('software.updates')!
	assert app.matching.len == 0 && app.status.contains('permissions blocked')
	app.close_app()
}
