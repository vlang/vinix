// SPDX-License-Identifier: GPL-2.0-or-later
// Compiled beside the actual Software app by distribution-check.v.
module main

import json2
import os
import ui2
import time
import desktop.packagecore
import tools.packages.pkgprotocol

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

fn fixture_review(operation string, names []string) pkgprotocol.Review {
	return pkgprotocol.Review{
		format: 1, operation: operation, names: names, architecture: 'aarch64', generation: 3,
		target_generation: if operation == 'rollback' { u64(2) } else { u64(0) },
		fingerprint: 'c'.repeat(64), requested: ['editor'], disk_needed: 4096, disk_available: 65536, disk_reserve: 1024,
		rows: [
			pkgprotocol.ReviewPackage{ id: 'editor', name: 'Editor', description: 'Write documents', version: '2.0.0', installed_version: '1.0.0', architecture: 'aarch64', kind: 'linux', runtime: 'runtime', repository: 'trusted', public_key: 'a'.repeat(64), license: 'MIT', permissions: ['files'], requested: true, action: 'update' },
			pkgprotocol.ReviewPackage{ id: 'runtime', name: 'Runtime', description: 'Required shared runtime', version: '2.0.0', installed_version: '1.0.0', architecture: 'aarch64', kind: 'runtime', repository: 'runtime-publisher', public_key: 'b'.repeat(64), license: 'Vendor-EULA', proprietary: true, firmware: true, permissions: ['network', 'process'], action: 'update' },
		]
	}
}

fn wait_for_software(mut app SoftwareApp) {
	for _ in 0 .. 500 {
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

fn main() {
	// This same executable is a literal-argv service fixture for asynchronous
	// view/run transitions. It deliberately returns useful launch diagnostics.
	if os.args.len > 1 {
		if os.args[1] == 'view' {
			println(json2.encode(SoftwareView{ format: 1, architecture: 'aarch64' }))
			return
		}
		if os.args[1] == 'run' {
			assert os.args[2..] == ['editor', '/private/tmp/document with spaces; \$literal.txt']
			eprintln('fixture: ordinary user session required')
			exit(19)
		}
		if os.args[1] == 'review' {
			if os.args.len > 3 && os.args[3] == 'broken' { eprintln('fixture: dependency unavailable'); exit(17) }
			review := fixture_review(os.args[2], os.args[3..])
			println(json2.encode(if os.args.len > 3 && os.args[3] == 'wrong-format' {
				pkgprotocol.Review{ ...review, format: 2 }
			} else if os.args.len > 3 && os.args[3] == 'wrong-intent' {
				pkgprotocol.Review{ ...review, names: ['other'] }
			} else { review }))
			return
		}
		if os.args[1] == 'apply' {
			assert os.args[2..] == ['c'.repeat(64), 'install', 'editor']
			eprintln('fixture: package review is stale; review again')
			exit(23)
		}
		if os.args[1] == 'lease-hold' { time.sleep(200 * time.millisecond); return }
		panic('unexpected fixture service command')
	}
	mut app := SoftwareApp{ query: []u8{cap: 256}, output: []u8{cap: 8192} }
	view := SoftwareView{
		format:       1
		architecture: 'aarch64'
		launch_user: 'alex'
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
	assert tree.children.any(it.id == 'software.run')
	assert tree.children.any(it.id == 'software.run' && it.text == 'Launch as alex')
	compact := app.build(ui2.rect(0, 0, 480, 300)) or { panic(err) }
	assert compact.children.len == 2
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
	println('Software UI: catalog, complete dependency review, literal confirmation, stale-plan failure, paging, diagnostics and close guard passed')
}
