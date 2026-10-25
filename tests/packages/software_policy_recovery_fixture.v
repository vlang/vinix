// SPDX-License-Identifier: GPL-2.0-or-later
// Staged beside the actual Software implementation by the recovery host driver.
module main

import json2
import os
import time
import ui2

fn C.vinix_heap_count() u32

const policy_recovery_path = '/private/tmp/部署 policy; $literal é.json'

fn policy_recovery_require(ok bool, message string) ! {
	if !ok { return error(message) }
}

// All side effects and checks remain active in production builds.
fn policy_recovery_service(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_POLICY_RECOVERY')
	if mode == '' || args.len < 2 { return false }
	if args[1] == 'policy-review' {
		policy_recovery_require(args == [args[0], 'policy-review', policy_recovery_path],
			'review child received a different literal draft')!
		println(json2.encode(fixture_policy_review()))
		return true
	}
	policy_recovery_require(args == [args[0], 'policy'], 'recovery child received unexpected argv')!
	text := json2.encode(fixture_policy_document())
	defer { unsafe { text.free() } }
	if mode == 'invalid' { print('{"format":1}'); return true }
	if mode == 'failed' { eprintln('fixture: active policy is temporarily unavailable'); exit(23) }
	policy_recovery_require(mode in ['partial', 'complete', 'success']!, 'unknown recovery child mode')!
	if mode == 'success' { print(text); return true }
	length := if mode == 'partial' { 17 } else { text.len }
	print(text[..length]); flush_stdout()
	mut release := u8(0)
	if C.read(0, unsafe { &release }, 1) != 1 || release != `x` {
		return error('policy recovery child barrier was not released')
	}
	if mode == 'partial' { print(text[length..]) }
	return true
}

fn policy_recovery_element(tree ui2.Element, id string) !ui2.Element {
	for child in tree.children { if child.id == id { return child } }
	return error('policy recovery element is absent: ' + id)
}

fn policy_recovery_geometry(mut app SoftwareApp, state string) ! {
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 400, 300), ui2.rect(0, 0, 180, 96),
		ui2.rect(0, 0, 180, 129), ui2.rect(0, 0, 180, 130), ui2.rect(0, 0, 180, 167),
		ui2.rect(0, 0, 180, 168), ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 319, 239)]! {
		tree := app.build(size)!
		defer { free_window_tree(tree) }
		for index, child in tree.children {
			frame := child.frame
			policy_recovery_require(frame.x >= 0 && frame.y >= 0 && frame.width > 0 && frame.height > 0
				&& frame.x + frame.width <= size.width && frame.y + frame.height <= size.height,
				'policy recovery element leaves canvas: ' + child.id)!
			for other in tree.children[index + 1..] {
				policy_recovery_require(frame.x + frame.width <= other.frame.x || other.frame.x + other.frame.width <= frame.x
					|| frame.y + frame.height <= other.frame.y || other.frame.y + other.frame.height <= frame.y,
					'policy recovery elements overlap: ' + child.id + '/' + other.id)!
			}
		}
		policy_recovery_require(tree.children.any(it.text == app.status), 'compact policy omits status')!
		policy_recovery_require(!tree.children.any(it.id == 'software.policy.confirm'), 'compact policy exposes confirmation')!
		mut next_y := 84
		for child in tree.children {
			if child.id in ['software.policy.read', 'software.policy.reload', 'software.failure']! { next_y += 38 }
		}
		policy_recovery_require(tree.children.any(it.id == 'software.progress')
			== (app.progress_seen && size.height >= 240 && next_y <= size.height - 110),
			'compact policy progress is absent or overlaps its action rows')!
		if state in ['stopped', 'failed', 'invalid']! {
			_ := policy_recovery_element(tree, 'software.policy.back')!
			policy_recovery_require(tree.children.any(it.id == 'software.policy.reload') == (size.height >= 130),
				'compact policy recovery control does not follow its minimum height')!
			if size.height >= 130 {
				button := policy_recovery_element(tree, 'software.policy.reload')!
				policy_recovery_require(button.text == 'Reload policy' && button.frame.y == 84,
					'compact policy recovery button has wrong label or position')!
			}
		} else {
			policy_recovery_require(!tree.children.any(it.id == 'software.policy.reload'),
				'compact policy exposes reload outside idle recovery')!
		}
		if state == 'active' { _ := policy_recovery_element(tree, 'software.policy.stop')! }
		if state == 'review' { _ := policy_recovery_element(tree, 'software.policy.cancel')! }
		if state == 'ready' {
			policy_recovery_require(tree.children.any(it.id == 'software.policy.read') == (size.height >= 220),
				'loaded compact policy lost its reader')!
		}
		if state == 'failed' {
			policy_recovery_require(tree.children.any(it.id == 'software.failure') == (size.height >= 168),
				'compact policy diagnostics do not follow their minimum height')!
		}
	}
}

fn policy_recovery_wait(mut app SoftwareApp, expected_output int) ! {
	for _ in 0 .. 5000 {
		app.poll()
		if expected_output > 0 && app.output.len == expected_output && app.worker != unsafe { nil } { return }
		if expected_output == 0 && app.worker == unsafe { nil } { return }
		time.sleep(time.millisecond)
	}
	return error('policy recovery child did not reach expected state')
}

fn policy_recovery_activate(mut app SoftwareApp, id string) ! {
	tree := app.build(ui2.rect(0, 0, 320, 240))!
	defer { free_window_tree(tree) }
	button := policy_recovery_element(tree, id)!
	app.handle(button.id)!
}

fn policy_recovery_functional() ! {
	defer { os.unsetenv('VINIX_SOFTWARE_POLICY_RECOVERY') }
	complete := json2.encode(fixture_policy_document())
	defer { unsafe { complete.free() } }
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: 'kept query'.bytes(), selected: 5, filter: 1 }
	defer { app.close_app() }
	for mode in ['partial', 'complete', 'failed', 'invalid']! {
		os.setenv('VINIX_SOFTWARE_POLICY_RECOVERY', mode, true)
		app.handle(if app.policy_mode { 'software.policy.reload' } else { 'software.policy' })!
		app.initialize_policy_path()
		software_repository_text(mut app.policy_path, policy_recovery_path)
		policy_recovery_require(app.worker != unsafe { nil } && app.worker.args == ['policy']
			&& app.policy_mode && !app.admin_prompt && app.prepare_close(), 'initial policy read did not start')!
		pid := app.worker.pid
		if mode in ['partial', 'complete']! {
			policy_recovery_wait(mut app, if mode == 'partial' { 17 } else { complete.len })!
			policy_recovery_require(app.worker.is_alive() && app.policy_read_running() && !app.policy_ready,
				'partial/complete read was admitted before child exit')!
			policy_recovery_geometry(mut app, 'active')!
			app.handle('software.policy.reload')!
			policy_recovery_require(app.worker.pid == pid, 'busy policy accepted another reload')!
			policy_recovery_activate(mut app, 'software.policy.stop')!
			policy_recovery_require(app.worker == unsafe { nil } && C.kill(pid, 0) != 0
				&& app.policy_worker == .none && !app.worker_view && !app.worker_review
				&& app.output.len == 0 && app.status.contains('stopped'), 'stopped policy child was not reaped and retired')!
		} else {
			policy_recovery_wait(mut app, 0)!
			policy_recovery_require(C.kill(pid, 0) != 0, 'failed policy child was not reaped')!
			policy_recovery_require(if mode == 'failed' { app.failure_pages.len > 0 && app.status.contains('temporarily unavailable') }
				else { app.status.contains('Invalid organization policy response') }, 'failure did not reach expected recovery state')!
		}
		policy_recovery_require(!app.policy_ready && app.policy_pages.len == 0
			&& editor_bytes_text(app.policy_path) == policy_recovery_path, 'failed/stopped read lost literal retry draft')!
		policy_recovery_geometry(mut app, if mode in ['partial', 'complete']! { 'stopped' } else { mode })!
		if mode == 'failed' {
			app.progress_seen = true
			policy_recovery_geometry(mut app, 'failed')!
			app.progress_seen = false
		}
		os.setenv('VINIX_SOFTWARE_POLICY_RECOVERY', 'success', true)
		policy_recovery_activate(mut app, 'software.policy.reload')!
		policy_recovery_require(app.worker != unsafe { nil } && app.worker.args == ['policy']
			&& !app.admin_prompt && editor_bytes_text(app.policy_path) == policy_recovery_path,
			'rendered reload did not start the fresh read or preserve the literal draft')!
		policy_recovery_wait(mut app, 0)!
		policy_recovery_require(app.policy_ready && app.policy_document.policy.allow_firmware
			&& app.policy_pages.len > 0 && editor_bytes_text(app.policy_path) == policy_recovery_path,
			'rendered policy reload did not recover the document')!
		policy_recovery_geometry(mut app, 'ready')!
		app.progress_seen = true
		policy_recovery_geometry(mut app, 'ready')!
		app.progress_seen = false
		app.handle('software.policy.review')!
		policy_recovery_require(app.worker.args == ['policy-review', policy_recovery_path], 'retry review lost literal draft argv')!
		policy_recovery_wait(mut app, 0)!
		policy_recovery_require(app.policy_review_ready && app.policy_pending == policy_recovery_path,
			'retry could not prepare a fresh review')!
		policy_recovery_geometry(mut app, 'review')!
		app.handle('software.policy.cancel')!
	}
	policy_recovery_require(editor_bytes_text(app.query) == 'kept query' && app.selected == 5 && app.filter == 1,
		'policy recovery changed catalog state')!
	println('POLICY RECOVERY four real child Stop/failure/invalid recovery paths retain literal draft and reach fresh review PASS')
	println('POLICY RECOVERY nine compact/tiny canvases, lifecycle guards and nonoverlapping geometry PASS')
}

fn policy_recovery_render_cycle(mut app SoftwareApp) ! {
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 400, 300), ui2.rect(0, 0, 180, 96),
		ui2.rect(0, 0, 180, 129), ui2.rect(0, 0, 180, 130), ui2.rect(0, 0, 180, 167),
		ui2.rect(0, 0, 180, 168), ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 319, 239)]! {
		free_window_tree(app.build(size)!)
	}
}

fn policy_recovery_memory() ! {
	$if track_heap ? {
		C.vinix_heap_begin()
		positive := unsafe { malloc(37) }
		positive_bytes := C.vinix_heap_end(); positive_records := C.vinix_heap_count()
		unsafe { free(positive) }
		policy_recovery_require(positive_bytes == 37 && positive_records == 1, 'heap tracker missed positive control')!
		C.vinix_heap_begin()
		balanced := unsafe { malloc(37) }
		unsafe { free(balanced) }
		balanced_bytes := C.vinix_heap_end()
		policy_recovery_require(balanced_bytes == 0 && C.vinix_heap_count() == 0, 'heap tracker missed balanced free control')!
		mut app := SoftwareApp{ policy_mode: true, output: []u8{cap: 8192}, status: 'Reload the current policy.' }
		defer { app.close_app() }
		app.initialize_policy_path(); software_repository_text(mut app.policy_path, policy_recovery_path)
		app.output << 'fixture: active policy is temporarily unavailable'.bytes()
		app.capture_failure(['policy'], 23)
		for _ in 0 .. 2 { policy_recovery_render_cycle(mut app)! }
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { policy_recovery_render_cycle(mut app)! }
		kept := C.vinix_heap_end(); records := C.vinix_heap_count()
		policy_recovery_require(kept == 0 && records == 0, 'compact policy recovery render retained allocations')!
		println('POLICY RECOVERY 1000 cycles / 9000 trees retain 0 bytes / 0 records PASS')
	}
}

fn check_software_policy_recovery() ! {
	policy_recovery_functional()!
	policy_recovery_memory()!
	println('POLICY RECOVERY explicit production-safe checks PASS')
}
