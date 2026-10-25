// SPDX-License-Identifier: GPL-2.0-or-later
// Staged beside the actual Software implementation by the compact host driver.
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

fn C.vinix_heap_count() u32

const compact_snapshot_partial = '/private/tmp/部署 with spaces; $literal/snapshot-compact-partial.json'
const compact_snapshot_complete = '/private/tmp/部署 with spaces; $literal/snapshot-compact-complete.json'
const compact_snapshot_failed = '/private/tmp/部署 with spaces; $literal/snapshot-compact-late-failed.json'

fn compact_snapshot_require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn compact_snapshot_receipt(path string) string {
	return json2.encode(pkgprotocol.DeploymentSnapshotSaved{ generation: 7, architecture: 'aarch64',
		destination: path, sha256: 'd'.repeat(64), roots: 2, packages: 5 })
}

// This private service is dispatched before the historical service fixture.
// Every barrier has an explicit checked side effect, including under -prod.
fn compact_snapshot_service(args []string) !bool {
	if args.len == 4 && args[1] == '--json' && args[2] == 'deployment-audit'
		&& args[3] == compact_snapshot_complete {
		print(json2.encode(pkgprotocol.DeploymentAudit{ generation: 4242, architecture: 'aarch64',
			deployment_sha256: 'e'.repeat(64), matches: true }))
		return true
	}
	if args.len < 4 || args[3] !in [compact_snapshot_partial, compact_snapshot_complete, compact_snapshot_failed]! {
		return false
	}
	compact_snapshot_require(args.len == 4 && args[1] == '--json' && args[2] == 'deployment-snapshot-save',
		'compact child received different literal argv')!
	text := compact_snapshot_receipt(args[3])
	defer { unsafe { text.free() } }
	print(text[..17]); flush_stdout()
	if args[3] != compact_snapshot_partial { print(text[17..]); flush_stdout() }
	mut release := u8(0)
	if C.read(0, unsafe { &release }, 1) != 1 || release != `x` {
		return error('compact snapshot child barrier was not released')
	}
	if args[3] == compact_snapshot_partial { print(text[17..]); flush_stdout() }
	if args[3] == compact_snapshot_failed {
		eprintln('Saved, but directory flush failed. Inspect the destination before retrying.')
		exit(24)
	}
	return true
}

fn compact_snapshot_element(tree ui2.Element, id string) !ui2.Element {
	for child in tree.children { if child.id == id { return child } }
	return error('compact snapshot element is absent: ' + id)
}

fn compact_snapshot_geometry(mut app SoftwareApp, width int, height int, state string) ! {
	tree := app.build(ui2.rect(0, 0, f64(width), f64(height)))!
	defer { free_window_tree(tree) }
	for index, child in tree.children {
		frame := child.frame
		compact_snapshot_require(frame.x >= 0 && frame.y >= 0 && frame.width > 0 && frame.height > 0
			&& frame.x + frame.width <= width && frame.y + frame.height <= height,
			'compact snapshot element leaves canvas')!
		for other in tree.children[index + 1..] {
			compact_snapshot_require(frame.x + frame.width <= other.frame.x || other.frame.x + other.frame.width <= frame.x
				|| frame.y + frame.height <= other.frame.y || other.frame.y + other.frame.height <= frame.y,
				'compact snapshot elements overlap')!
		}
	}
	compact_snapshot_require(tree.children.any(it.text == app.status), 'compact snapshot status is absent')!
	if width < 320 || height < 240 {
		compact_snapshot_require(tree.children.any(it.text.contains('enlarge for details'))
			&& !tree.children.any(it.id in ['software.deployment.path', 'software.snapshot.save', 'software.report.read']!),
			'tiny snapshot fallback exposes a clipped editor or receipt action')!
		if state == 'active' {
			compact_snapshot_require(!tree.children.any(it.id in ['software.snapshot.back', 'software.failure']!)
				&& tree.children.any(it.text == 'Wait for saving to finish.' && it.frame.y == 46),
				'tiny writer exposes navigation or omits its wait label')!
		} else {
			back := compact_snapshot_element(tree, 'software.snapshot.back')!
			compact_snapshot_require(back.frame.y == 46, 'tiny snapshot Back leaves its action row')!
			if state == 'failure' { _ := compact_snapshot_element(tree, 'software.failure')! }
		}
		return
	}
	if state == 'ready' {
		_ := compact_snapshot_element(tree, 'software.snapshot.back')!
		compact_snapshot_require(!tree.children.any(it.id in ['software.deployment.path', 'software.snapshot.save']!),
			'ready compact snapshot still exposes draft editing')!
		_ := compact_snapshot_element(tree, 'software.report.read')!
		return
	}
	field := compact_snapshot_element(tree, 'software.deployment.path')!
	compact_snapshot_require(field.frame.y == 64 && field.frame.height == 28
		&& field.text == editor_bytes_text(app.deployment_path), 'compact draft path is not editable at the expected location')!
	compact_snapshot_require(tree.children.any(it.text == 'New deployment file (absolute path)' && it.frame.y == 42),
		'compact draft path label is absent')!
	if state == 'active' {
		compact_snapshot_require(!tree.children.any(it.id in ['software.snapshot.back', 'software.snapshot.save', 'software.failure']!),
			'compact writer exposes navigation or Save')!
		compact_snapshot_require(tree.children.any(it.text == 'Wait for saving to finish.' && it.frame.y == 104),
			'compact writer wait label is absent')!
	} else {
		save := compact_snapshot_element(tree, 'software.snapshot.save')!
		back := compact_snapshot_element(tree, 'software.snapshot.back')!
		compact_snapshot_require(save.frame.y == 104 && back.frame.y == 8, 'compact draft actions moved out of their rows')!
		if state == 'failure' { _ := compact_snapshot_element(tree, 'software.failure')! }
	}
}

fn compact_snapshot_both_sizes(mut app SoftwareApp, state string) ! {
	compact_snapshot_geometry(mut app, 320, 240, state)!
	compact_snapshot_geometry(mut app, 400, 300, state)!
	compact_snapshot_geometry(mut app, 180, 96, state)!
	compact_snapshot_geometry(mut app, 319, 239, state)!
	compact_snapshot_geometry(mut app, 319, 240, state)!
	compact_snapshot_geometry(mut app, 320, 239, state)!
}

fn compact_snapshot_wait(mut app SoftwareApp) ! {
	for _ in 0 .. 5000 {
		app.poll()
		if app.worker == unsafe { nil } { return }
		time.sleep(time.millisecond)
	}
	return error('compact snapshot child did not finish')
}

fn compact_snapshot_functional() ! {
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: 'kept query'.bytes(), selected: 5, filter: 1 }
	defer { app.close_app() }
	app.handle('software.deployment')!
	app.handle('software.deployment.snapshot')!
	app.handle('software.snapshot.save')!
	compact_snapshot_require(app.worker == unsafe { nil } && app.status.contains('absolute'),
		'empty compact filename started a writer')!
	app.paste_input(compact_snapshot_complete); app.key_input('\x01')
	for input in ['\x1b', '\r', '\n', 'bad\x00path', '/bad\xc2\x85path', '\xff']! {
		app.paste_input(input)
		compact_snapshot_require(app.focus && app.select_all && app.snapshot_mode
			&& editor_bytes_text(app.deployment_path) == compact_snapshot_complete
			&& app.worker == unsafe { nil } && app.status.contains('field was kept intact'),
			'invalid paste changed compact filename or editing state')!
	}
	compact_snapshot_both_sizes(mut app, 'draft')!
	println('COMPACT SNAPSHOT six canvas sizes, draft geometry and invalid paste PASS')
	for path in [compact_snapshot_partial, compact_snapshot_failed, compact_snapshot_complete]! {
		app.begin_deployment_snapshot(); app.paste_input(path)
		app.handle('software.snapshot.save')!
		expected := compact_snapshot_receipt(path)
		expected_length := if path == compact_snapshot_partial { 17 } else { expected.len }
		unsafe { expected.free() }
		for _ in 0 .. 5000 {
			app.poll()
			if app.output.len == expected_length { break }
			time.sleep(time.millisecond)
		}
		compact_snapshot_require(app.worker != unsafe { nil }, 'compact writer ended before its barrier')!
		pid := app.worker.pid
		compact_snapshot_require(app.worker.is_alive() && app.output.len == expected_length
			&& app.worker_snapshot && app.worker_view && !app.snapshot_ready && app.details_pages.len == 0
			&& app.worker.args == ['--json', 'deployment-snapshot-save', path] && !app.admin_prompt,
			'compact writer did not reach the admitted partial/complete barrier')!
		compact_snapshot_require(!app.prepare_close(), 'compact snapshot writer allowed close')!
		for event in ['software.snapshot.back', 'software.snapshot.another', 'software.snapshot.save',
			'software.snapshot.audit', 'software.snapshot.review', 'software.snapshot.export', 'software.deployment.path',
			'software.deployment.stop', 'software.cancel', 'software.verify.stop', 'software.failure', 'software.report.read']! {
			app.handle(event)!
		}
		for input in ['\x1b', '\r', '\x01', '\x08', '/changed.json']! { app.key_input(input); app.paste_input(input) }
		compact_snapshot_require(app.worker != unsafe { nil } && app.worker.pid == pid && app.worker.is_alive()
			&& app.snapshot_mode && !app.snapshot_ready && !app.failure_mode && !app.report_reader_mode
			&& app.snapshot_pending == path && editor_bytes_text(app.deployment_path) == path && !app.focus && !app.select_all,
			'active compact writer accepted navigation, input or early receipt')!
		compact_snapshot_both_sizes(mut app, 'active')!
		app.worker.stdin_write('x')
		compact_snapshot_wait(mut app)!
		compact_snapshot_require(app.prepare_close() && !app.worker_snapshot, 'finished compact writer still owns close guard')!
		if path == compact_snapshot_failed {
			compact_snapshot_require(!app.snapshot_ready && app.details_pages.len == 0 && app.failure_pages.len > 0
				&& app.status.contains('Inspect the destination'), 'late failure admitted an early complete receipt')!
			compact_snapshot_both_sizes(mut app, 'failure')!
			app.handle('software.failure')!
			compact_snapshot_require(app.failure_mode, 'compact failure action did not open diagnostics')!
			app.key_input('\x1b')
			compact_snapshot_require(app.snapshot_mode && !app.failure_mode, 'failure Back lost the compact draft')!
		} else {
			compact_snapshot_require(app.snapshot_ready && app.snapshot_saved.destination == path
				&& app.snapshot_pending == path, 'successful compact writer lost its literal captured destination')!
			compact_snapshot_both_sizes(mut app, 'ready')!
		}
	}
	// A changed form must never replace the successfully captured destination.
	software_repository_text(mut app.deployment_path, '/must-not-be-used.json')
	app.handle('software.snapshot.audit')!
	compact_snapshot_require(app.worker != unsafe { nil }
		&& app.worker.args == ['--json', 'deployment-audit', compact_snapshot_complete] && !app.admin_prompt,
		'fresh audit did not use the captured literal filename')!
	compact_snapshot_wait(mut app)!
	compact_snapshot_require(app.audit_ready && app.audit_path == compact_snapshot_complete
		&& app.audit_snapshot.generation == 4242 && app.audit_snapshot.matches
		&& app.audit_snapshot.deployment_sha256 == 'e'.repeat(64),
		'actual audit child did not receive the captured literal filename')!
	compact_snapshot_require(editor_bytes_text(app.query) == 'kept query' && app.selected == 5 && app.filter == 1,
		'compact snapshot changed the catalog selection')!
	println('COMPACT SNAPSHOT three real child barriers, close/navigation guards and captured literal path PASS')
}

fn compact_snapshot_render_cycle(mut app SoftwareApp) ! {
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 400, 300), ui2.rect(0, 0, 180, 96),
		ui2.rect(0, 0, 319, 239), ui2.rect(0, 0, 319, 240), ui2.rect(0, 0, 320, 239)]! {
		free_window_tree(app.build(size)!)
	}
}

fn compact_snapshot_memory() ! {
	$if track_heap ? {
		C.vinix_heap_begin()
		positive := unsafe { malloc(37) }
		positive_bytes := C.vinix_heap_end()
		positive_records := C.vinix_heap_count()
		unsafe { free(positive) }
		compact_snapshot_require(positive_bytes == 37 && positive_records == 1,
			'tracker did not observe its positive allocation control')!
		C.vinix_heap_begin()
		balanced := unsafe { malloc(37) }
		unsafe { free(balanced) }
		balanced_bytes := C.vinix_heap_end()
		compact_snapshot_require(balanced_bytes == 0 && C.vinix_heap_count() == 0,
			'tracker did not observe its balanced free control')!
		mut draft := SoftwareApp{ deployment_mode: true, output: []u8{cap: 8192} }
		mut ready := SoftwareApp{ deployment_mode: true, output: []u8{cap: 8192} }
		mut failed := SoftwareApp{ deployment_mode: true, output: []u8{cap: 8192} }
		defer { draft.close_app(); ready.close_app(); failed.close_app() }
		draft.begin_deployment_snapshot(); draft.paste_input(compact_snapshot_complete)
		ready.begin_deployment_snapshot(); ready.snapshot_pending = compact_snapshot_complete.clone()
		text := compact_snapshot_receipt(compact_snapshot_complete)
		for byte in text { ready.output << byte }
		unsafe { text.free() }
		compact_snapshot_require(ready.load_deployment_snapshot(), 'render fixture could not admit its receipt')!
		failed.begin_deployment_snapshot(); failed.paste_input(compact_snapshot_failed)
		failed.output << 'Saved, but directory flush failed. Inspect the destination before retrying.'.bytes()
		failed.capture_failure(['--json', 'deployment-snapshot-save', compact_snapshot_failed], 24)
		failed.set_status('Saved, but directory flush failed. Inspect the destination before retrying.')
		for _ in 0 .. 2 { compact_snapshot_render_cycle(mut draft)!; compact_snapshot_render_cycle(mut ready)!; compact_snapshot_render_cycle(mut failed)! }
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { compact_snapshot_render_cycle(mut draft)!; compact_snapshot_render_cycle(mut ready)!; compact_snapshot_render_cycle(mut failed)! }
		kept := C.vinix_heap_end()
		records := C.vinix_heap_count()
		compact_snapshot_require(kept == 0 && records == 0, '1000 compact draft/ready/failure render cycles retained allocations')!
		println('COMPACT SNAPSHOT 1000 cycles / 18000 compact trees retain 0 bytes / 0 records PASS')
	} $else {
		println('COMPACT SNAPSHOT tracking disabled; render retention measured in tracked variants')
	}
}

fn check_software_snapshot_compact() ! {
	compact_snapshot_functional()!
	compact_snapshot_memory()!
	println('COMPACT SNAPSHOT explicit production-safe checks PASS')
}
