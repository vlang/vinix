// SPDX-License-Identifier: GPL-2.0-or-later
// Explicit host checks, including when assertions are omitted by -prod.
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol

const compact_mirror_destination = '/private/tmp/部署 with spaces; $literal/export'
const compact_mirror_source = '/private/tmp/部署 with spaces; $literal/deployment.json'

fn compact_mirror_require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn compact_mirror_wire(locked bool, changed bool) string {
	mut base := software_snapshot_export_review(compact_mirror_source, false)
	defer { base.close() }
	response := pkgprotocol.MirrorReview{ ...base.mirror, input_destination: compact_mirror_destination,
		destination: compact_mirror_destination }
	return if locked { json2.encode(pkgprotocol.DeploymentMirrorReview{ ...base, mirror: response,
		deployment_sha256: if changed { 'e'.repeat(64) } else { base.deployment_sha256 } }) }
		else { json2.encode(response) }
}

fn compact_mirror_service(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_COMPACT_MIRROR')
	if mode == 'writer' && args.len > 2 && args[1] == '--progress' {
		compact_mirror_require(args == [args[0], '--progress', 'mirror-deployment-apply', 'd'.repeat(64),
			compact_mirror_destination, compact_mirror_source], 'publication child received different frozen literal argv')!
		progress := pkgprotocol.Progress{ phase: 'copy', package: 'editor', path: 'payload', current: 1, total: 2 }
		progress.validate()!
		println(pkgprotocol.progress_prefix + json2.encode(progress))
		println('Export writer held.'); flush_stdout()
		mut release := u8(0)
		compact_mirror_require(C.read(0, unsafe { &release }, 1) == 1 && release == `x`, 'publication barrier was not released')!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		println('Offline deployment mirror ready: ' + compact_mirror_destination + '/_deployment.json')
		return true
	}
	if mode == '' || args.len < 2 || args[1] !in ['mirror-review', 'mirror-deployment-review']! { return false }
	locked := args[1] == 'mirror-deployment-review'
	compact_mirror_require(args == if locked { [args[0], 'mirror-deployment-review', compact_mirror_destination, compact_mirror_source] }
		else { [args[0], 'mirror-review', compact_mirror_destination, 'editor'] }, 'compact mirror child received different literal argv')!
	if mode == 'malformed' { print('{"format":1}'); return true }
	if mode == 'diagnostic' { eprintln('Export destination is unavailable. Restore access and review again.'); exit(24) }
	text := compact_mirror_wire(locked, mode == 'changed-source')
	defer { unsafe { text.free() } }
	if mode.starts_with('held-') {
		print(if mode == 'held-partial' { text[..17] } else { text }); flush_stdout()
		mut release := u8(0)
		compact_mirror_require(C.read(0, unsafe { &release }, 1) == 1 && release == `x`, 'compact mirror barrier was not released')!
		if mode == 'held-partial' { print(text[17..]) }
	} else { print(text) }
	return true
}

fn compact_mirror_element(tree ui2.Element, id string) !ui2.Element {
	for child in tree.children { if child.id == id { return child } }
	return error('compact mirror element absent: ' + id)
}

fn compact_mirror_geometry(mut app SoftwareApp, state string) ! {
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 400, 300), ui2.rect(0, 0, 180, 96),
		ui2.rect(0, 0, 319, 239), ui2.rect(0, 0, 319, 240), ui2.rect(0, 0, 320, 239)]! {
		tree := app.build(size)!
		defer { free_window_tree(tree) }
		for index, child in tree.children {
			f := child.frame
			compact_mirror_require(f.x >= 0 && f.y >= 0 && f.width > 0 && f.height > 0
				&& f.x + f.width <= size.width && f.y + f.height <= size.height, 'compact mirror element leaves canvas')!
			for other in tree.children[index + 1..] {
				compact_mirror_require(f.x + f.width <= other.frame.x || other.frame.x + other.frame.width <= f.x
					|| f.y + f.height <= other.frame.y || other.frame.y + other.frame.height <= f.y, 'compact mirror elements overlap')!
			}
		}
		compact_mirror_require(tree.children.any(it.text == app.status), 'compact mirror status is absent')!
		compact_mirror_require(!tree.children.any(it.id == 'software.confirm'), 'compact mirror exposes publication confirmation')!
		tiny := size.width < 320 || size.height < 240
		if state == 'publication' {
			compact_mirror_require(!tree.children.any(it.id in ['software.mirror.stop', 'software.mirror.back', 'software.cancel', 'software.mirror.review', 'software.report.read']!), 'publication exposes cancellation or draft actions')!
		} else if state == 'active' {
			_ := compact_mirror_element(tree, 'software.mirror.stop')!
			compact_mirror_require(!tree.children.any(it.id in ['software.mirror.back', 'software.cancel', 'software.mirror.review', 'software.report.read']!), 'active review exposes draft navigation')!
		} else if state == 'ready' {
			_ := compact_mirror_element(tree, 'software.cancel')!
			compact_mirror_require(tree.children.any(it.id == 'software.report.read') == !tiny, 'ready review reader visibility changed')!
		} else {
			_ := compact_mirror_element(tree, 'software.mirror.back')!
			compact_mirror_require(tree.children.any(it.id == 'software.mirror.review') == !tiny, 'compact draft Review visibility changed')!
			if !tiny {
				field := compact_mirror_element(tree, if app.mirror_locked && app.mirror_lock_focus { 'software.mirror.lock' } else { 'software.mirror.path' })!
				compact_mirror_require(field.frame.y == 64 && field.frame.height == 28, 'compact mirror field geometry changed')!
				compact_mirror_require(tree.children.any(it.id == 'software.mirror.scope') == (app.mirror_source == ''), 'saved source exposes mutable scope')!
				compact_mirror_require(tree.children.any(it.id == 'software.mirror.field') == app.mirror_locked, 'compact source navigation visibility changed')!
				if state == 'failure' { _ := compact_mirror_element(tree, 'software.failure')! }
			}
		}
		if tiny {
			compact_mirror_require(!tree.children.any(it.id in ['software.mirror.path', 'software.mirror.lock', 'software.mirror.scope', 'software.mirror.field', 'software.failure']!), 'tiny fallback exposes clipped draft controls')!
		}
	}
}

fn compact_mirror_finish(mut app SoftwareApp, held bool) ! {
	for _ in 0 .. 5000 {
		app.poll()
		if held && app.worker != unsafe { nil } && app.output.len > 0 { return }
		if !held && app.worker == unsafe { nil } { return }
		time.sleep(time.millisecond)
	}
	return error('compact mirror child did not reach expected boundary')
}

fn compact_mirror_held(mut app SoftwareApp, expected string) ! {
	for _ in 0 .. 5000 {
		app.poll()
		if app.output.len >= expected.len {
			compact_mirror_require(app.output.len == expected.len && app.worker != unsafe { nil }
				&& app.worker.is_alive() && !app.review_ready, 'review was admitted or did not hold exact response bytes')!
			for index, byte in app.output { compact_mirror_require(byte == expected[index], 'held response bytes changed')! }
			return
		}
		time.sleep(time.millisecond)
	}
	return error('review did not hold the complete expected partial/full response')
}

fn compact_mirror_replace(mut app SoftwareApp, event string, text string) ! {
	app.handle(event)!
	app.key_input('\x01'); app.paste_input(text)
}

fn check_software_mirror_compact() ! {
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: 'kept catalog query'.bytes(),
		filter: 1, selected: 0, rows: [SoftwareRow{ id: 'editor', name: 'Editor', requested: true, installed_version: '1.0.0' }] }
	defer { app.close_app(); os.unsetenv('VINIX_SOFTWARE_COMPACT_MIRROR') }
	app.handle('software.mirror')!
	compact_mirror_geometry(mut app, 'draft')!
	app.handle('software.mirror.review')!
	compact_mirror_require(app.worker == unsafe { nil } && app.status.contains('absolute new directory'), 'empty destination was admitted')!
	compact_mirror_replace(mut app, 'software.mirror.path', compact_mirror_destination)!
	for invalid in ['bad\npath', 'bad\xff', 'x'.repeat(4097), '\x1b'] {
		app.key_input('\x01'); app.paste_input(invalid)
		compact_mirror_require(editor_bytes_text(app.mirror_path) == compact_mirror_destination && app.select_all, 'invalid paste changed destination or selection')!
	}
	app.paste_input(compact_mirror_destination)
	os.setenv('VINIX_SOFTWARE_COMPACT_MIRROR', 'ok', true)
	for scope in 0 .. 3 {
		compact_mirror_require(app.mirror_locked == (scope == 2) && app.mirror_all == (scope == 1), 'scope did not cycle selected/installed/lock')!
		if scope == 2 {
			app.handle('software.mirror.field')!
			compact_mirror_require(app.mirror_lock_focus && !app.focus, 'source navigation retained input focus')!
			compact_mirror_replace(mut app, 'software.mirror.lock', compact_mirror_source)!
			compact_mirror_geometry(mut app, 'draft')!
			app.handle('software.mirror.field')!
		}
		compact_mirror_geometry(mut app, 'draft')!
		app.handle('software.mirror.review')!
		compact_mirror_require(app.worker != unsafe { nil } && app.worker.args == if scope == 2 {
			['mirror-deployment-review', compact_mirror_destination, compact_mirror_source]
		} else { ['mirror-review', compact_mirror_destination, 'editor'] }, 'draft review did not capture literal intent')!
		compact_mirror_finish(mut app, false)!
		compact_mirror_require(app.review_ready && app.mirror_pending == compact_mirror_destination, 'compact-authored proposal was not admitted')!
		compact_mirror_geometry(mut app, 'ready')!
		app.handle('software.confirm')!
		compact_mirror_require(app.worker == unsafe { nil } && app.mirror_details, 'publication skipped full path/package review')!
		app.handle('software.cancel')!
		app.handle('software.mirror.scope')!
	}
	compact_mirror_require(!app.mirror_locked && !app.mirror_all, 'scope cycle did not return to selected')!
	// Moving away from a source-selected lock restores the destination field.
	app.handle('software.mirror.scope')!; app.handle('software.mirror.scope')!
	app.handle('software.mirror.field')!
	compact_mirror_require(app.mirror_lock_focus, 'lock source was not selected')!
	app.handle('software.mirror.scope')!
	compact_mirror_geometry(mut app, 'draft')!
	app.handle('software.mirror.scope')!; app.handle('software.mirror.scope')!
	compact_mirror_geometry(mut app, 'draft')!
	compact_mirror_require(app.mirror_locked && app.mirror_lock_focus && !app.focus,
		'source selection or focus changed across a scope cycle')!
	app.handle('software.mirror.scope')!
	// Empty installed roots refuse before service invocation, independently of selection.
	app.rows[0] = SoftwareRow{ ...app.rows[0], requested: false }
	app.handle('software.mirror.scope')!; app.handle('software.mirror.review')!
	compact_mirror_require(app.worker == unsafe { nil } && app.status.contains('nonempty installed'), 'empty installed roots were admitted')!
	app.rows[0] = SoftwareRow{ ...app.rows[0], requested: true }
	app.handle('software.mirror.back')!
	// A saved receipt remains the authority even if stale editor storage changes.
	app.snapshot_mode = true; app.snapshot_ready = true
	app.snapshot_pending = compact_mirror_source.clone()
	app.snapshot_saved = software_snapshot_fixture_receipt(compact_mirror_source)
	app.handle_deployment_snapshot('software.snapshot.export')
	compact_mirror_require(app.mirror_path.len == 0 && app.mirror_source == compact_mirror_source
		&& app.mirror_source_sha256 == 'd'.repeat(64), 'saved receipt identity was not frozen')!
	compact_mirror_replace(mut app, 'software.mirror.path', compact_mirror_destination)!
	app.handle('software.mirror.field')!
	app.handle('software.mirror.lock')!; app.paste_input('/replacement.json')
	app.handle('software.mirror.scope')!
	software_repository_text(mut app.mirror_lock_path, '/stale-editor.json')
	compact_mirror_geometry(mut app, 'draft')!
	source_tree := app.build(ui2.rect(0, 0, 320, 240))!
	source_field := compact_mirror_element(source_tree, 'software.mirror.lock')!
	compact_mirror_require(source_field.text == compact_mirror_source && !app.focus && app.mirror_locked,
		'saved source display or edit gate changed')!
	free_window_tree(source_tree)
	for mode in ['malformed', 'diagnostic', 'changed-source']! {
		previous_failure_pages := app.failure_pages.len
		previous_failure_heading := app.failure_heading.clone()
		defer { unsafe { previous_failure_heading.free() } }
		os.setenv('VINIX_SOFTWARE_COMPACT_MIRROR', mode, true)
		app.handle('software.mirror.review')!
		compact_mirror_finish(mut app, false)!
		compact_mirror_require(!app.review_ready && app.review == ''
			&& app.mirror_source == compact_mirror_source && app.mirror_source_sha256 == 'd'.repeat(64), 'failed review lost frozen source or retained proposal: ' + mode)!
		if mode == 'changed-source' { compact_mirror_require(app.status == 'The saved deployment file changed. Save a new snapshot before exporting it.', 'changed saved digest was admitted')! }
		if mode == 'malformed' { compact_mirror_require(app.status == 'Unsupported or different offline export review. Review the export again.', 'malformed review lost refusal status')! }
		if mode == 'diagnostic' {
			compact_mirror_require(app.failure_pages.len > 0 && app.failure_heading == 'Offline repository export · exit 24'
				&& app.status == 'Export destination is unavailable. Restore access and review again.', 'failed child diagnostics were not retained')!
		} else {
			compact_mirror_require(app.failure_pages.len == previous_failure_pages && app.failure_heading == previous_failure_heading,
				'local response refusal replaced prior child diagnostics')!
		}
		compact_mirror_geometry(mut app, if app.failure_pages.len > 0 { 'failure' } else { 'draft' })!
		if app.failure_pages.len > 0 {
			app.handle('software.failure')!; compact_mirror_require(app.failure_mode, 'compact failure reader did not open')!
			app.handle('software.failure.back')!
		}
	}
	for mode in ['held-partial', 'held-complete']! {
		os.setenv('VINIX_SOFTWARE_COMPACT_MIRROR', mode, true)
		app.handle('software.mirror.review')!
		expected := compact_mirror_wire(true, false)
		defer { unsafe { expected.free() } }
		compact_mirror_held(mut app, if mode == 'held-partial' { expected[..17] } else { expected })!
		pid := app.worker.pid
		compact_mirror_require(!app.review_ready && app.mirror_review_running() && app.prepare_close(), 'live review was admitted or close became unsafe')!
		compact_mirror_geometry(mut app, 'active')!
		for event in ['software.mirror.field', 'software.mirror.path', 'software.mirror.lock', 'software.mirror.scope', 'software.mirror.review', 'software.mirror.back', 'software.confirm']! { app.handle(event)! }
		app.paste_input('/replacement'); app.key_input('replacement')
		compact_mirror_require(app.worker.pid == pid && app.mirror_pending == compact_mirror_destination
			&& app.mirror_lock_pending == compact_mirror_source && !app.review_ready, 'running review accepted mutable draft actions')!
		if mode == 'held-partial' {
			app.handle('software.mirror.stop')!
		} else { app.key_input('\x1b') }
		compact_mirror_require(app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && app.output.len == 0
			&& app.review == '' && app.mirror_mode && app.mirror_source == compact_mirror_source, 'Stop failed to reap review and retain draft')!
		compact_mirror_geometry(mut app, 'draft')!
	}
	os.setenv('VINIX_SOFTWARE_COMPACT_MIRROR', 'ok', true)
	app.handle('software.mirror.review')!; compact_mirror_finish(mut app, false)!
	compact_mirror_require(app.review_ready && app.mirror_lock_sha256 == 'd'.repeat(64), 'frozen-source retry failed')!
	seen := app.mirror_seen
	app.handle('software.report.read')!
	compact_mirror_require(app.report_reader_mode, 'compact proposal reader did not open')!
	app.handle('software.report.back')!
	compact_mirror_require(!app.report_reader_mode && app.mirror_pending == compact_mirror_destination
		&& app.mirror_seen == seen, 'proposal reader changed intent or path visitation')!
	// Enlarge and visit every path part before entering the full package review.
	for app.mirror_seen + 1 < app.mirror_pages.len { app.handle('software.mirror.next')! }
	app.handle('software.mirror.packages')!
	compact_mirror_require(!app.mirror_details && app.review_ready, 'full path gate did not reach package review')!
	full := app.build(ui2.rect(0, 0, 900, 660))!
	compact_mirror_require(full.children.any(it.id == 'software.confirm'), 'full package confirmation is absent')!
	free_window_tree(full)
	software_repository_text(mut app.mirror_path, '/changed-destination')
	software_repository_text(mut app.mirror_lock_path, '/changed-source')
	os.setenv('VINIX_SOFTWARE_COMPACT_MIRROR', 'writer', true)
	app.handle('software.confirm')!
	compact_mirror_require(app.worker != unsafe { nil }, 'full confirmation did not start publication')!
	compact_mirror_finish(mut app, true)!
	publication_pid := app.worker.pid
	compact_mirror_require(app.worker_mirror && !app.mirror_review_running() && app.progress_seen
		&& !app.prepare_close(), 'publication became cancelable or lost progress')!
	compact_mirror_geometry(mut app, 'publication')!
	for event in ['software.mirror.stop', 'software.cancel', 'software.mirror.back', 'software.mirror.field', 'software.report.read']! { app.handle(event)! }
	app.key_input('\x1b'); app.stop_mirror_review()
	compact_mirror_require(app.worker != unsafe { nil } && app.worker.pid == publication_pid
		&& C.kill(publication_pid, 0) == 0 && !app.prepare_close(), 'compact publication was stopped or navigated away')!
	release := u8(`x`)
	compact_mirror_require(C.write(app.worker.stdio_fd[0], unsafe { &release }, 1) == 1, 'could not release publication child')!
	compact_mirror_finish(mut app, false)!
	compact_mirror_require(C.kill(publication_pid, 0) != 0 && app.status.contains('/_deployment.json'), 'publication did not complete and reap')!
	app.handle('software.mirror.back')!
	compact_mirror_require(!app.mirror_mode && app.mirror_source == '' && app.mirror_source_sha256 == ''
		&& editor_bytes_text(app.query) == 'kept catalog query' && app.filter == 1 && app.selected == 0, 'Back lost catalog state or retained saved receipt')!
	println('COMPACT MIRROR six canvas sizes, destination/source/scope authoring, literal real-child argv, saved-source/digest refusal, recovery and Stop/reaping PASS')
	$if track_heap ? { check_software_mirror_compact_memory()! }
	println('COMPACT MIRROR explicit production-safe checks PASS')
}

fn check_software_mirror_compact_memory() ! {
	$if track_heap ? {
		C.vinix_heap_begin()
		positive := unsafe { malloc(37) }
		positive_bytes := C.vinix_heap_end(); positive_records := C.vinix_heap_count()
		unsafe { free(positive) }
		compact_mirror_require(positive_bytes == 37 && positive_records == 1, 'tracker missed positive allocation control')!
		C.vinix_heap_begin()
		balanced := unsafe { malloc(37) }
		unsafe { free(balanced) }
		compact_mirror_require(C.vinix_heap_end() == 0 && C.vinix_heap_count() == 0, 'tracker missed balanced free control')!
		mut app := SoftwareApp{ mirror_mode: true, status: 'Draft status'.clone() }
		app.initialize_mirror_field()
		software_repository_text(mut app.mirror_path, compact_mirror_destination)
		software_repository_text(mut app.mirror_lock_path, compact_mirror_source)
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for scope in 0 .. 3 {
					app.mirror_locked = scope == 2; app.mirror_all = scope == 1
					app.mirror_lock_focus = false
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					free_window_tree(app.build(ui2.rect(0, 0, 400, 300))!)
					app.handle_mirror('software.mirror.field')
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					free_window_tree(app.build(ui2.rect(0, 0, 180, 96))!)
				}
			}
		}
		kept := C.vinix_heap_end(); records := C.vinix_heap_count()
		compact_mirror_require(kept == 0 && records == 0, 'steady compact mirror rendering retained V bytes or records')!
		println('COMPACT MIRROR 1000 steady draft/navigation cycles / 12000 trees retain zero V bytes and records PASS')
	}
}
