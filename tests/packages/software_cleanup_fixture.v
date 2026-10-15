// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import desktop.packagecore
import tools.packages.pkgprotocol

fn fixture_cleanup_review() pkgprotocol.CleanupReview {
	return pkgprotocol.CleanupReview{ architecture: 'aarch64', generation: 50, previous: 49,
		fingerprint: 'd'.repeat(64), generations: []u64{len: 30, init: u64(index + 1)} }
}

fn software_cleanup_service_fixture(args []string) bool {
	if args[1..] == ['cleanup-review'] {
		mode := os.getenv('VINIX_SOFTWARE_CLEANUP_MODE')
		if mode == 'slow' { time.sleep(3 * time.second) }
		if mode == 'failed' { eprintln('generation lease is damaged; retain storage for inspection'); exit(21) }
		if mode == 'invalid' { println('{"format":1,"architecture":"aarch64"}'); return true }
		review := fixture_cleanup_review()
		println(json2.encode(pkgprotocol.CleanupReview{ ...review, generations: if os.exists(os.getenv('VINIX_SOFTWARE_CLEANUP_RECEIPT')) { []u64{} } else { review.generations } }))
		return true
	}
	admin := args.len > 1 && args[1] == 'admin'
	command := if admin { 2 } else { 1 }
	if args.len != command + 2 || args[command] != 'cleanup-apply' { return false }
	assert args[command + 1] == 'd'.repeat(64)
	if admin {
		mut bytes := [257]u8{}
		mut count := 0
		for count < bytes.len {
			assert C.read(0, &bytes[count], 1) == 1
			if bytes[count] == `\n` { break }; count++
		}
		assert unsafe { tos(&bytes[0], count) } == 'fixture secret é'
	}
	time.sleep(30 * time.millisecond)
	if os.getenv('VINIX_SOFTWARE_CLEANUP_MODE') == 'stale' { eprintln('generation cleanup review is stale; review cleanup again'); exit(29) }
	os.write_file(os.getenv('VINIX_SOFTWARE_CLEANUP_RECEIPT'), 'reviewed generations only') or { panic(err) }
	println('Obsolete generation cleanup completed.')
	return true
}

fn check_software_cleanup() ! {
	receipt := os.temp_dir() + '/vinix-software-cleanup-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_CLEANUP_RECEIPT', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_CLEANUP_RECEIPT'); os.unsetenv('VINIX_SOFTWARE_CLEANUP_MODE') }
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		output: []u8{cap: 8192}, query: 'editor'.bytes(), filter: 2, selected: 0,
		rows: [SoftwareRow{ id: 'editor', name: 'Editor', installed_version: '1.0.0' }] }
	defer { app.close_app() }
	app.handle('software.cleanup')!
	assert app.cleanup_mode && app.worker.args == ['cleanup-review'] && !app.admin_prompt && app.prepare_close()
	app.handle('software.confirm')!; app.handle('software.cleanup.confirm')!
	assert app.worker.args == ['cleanup-review']
	wait_for_software(mut app)
	assert app.cleanup_ready && app.cleanup_snapshot.generations.len == 30
	assert app.cleanup_snapshot.generation == 50 && app.cleanup_summary.contains('Rollback: 49')
	tree := app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.id == 'software.cleanup.confirm')
	assert tree.children.any(it.text.contains('personal data are retained'))
	assert tree.children.any(it.text == 'Remove generation 1')
	free_window_tree(tree)
	app.handle('software.cleanup.down')!; assert app.cleanup_scroll > 0
	free_window_tree(app.build(ui2.rect(0, 0, 900, 900))!); app.handle('software.cleanup.up')!; assert app.cleanup_scroll >= 0
	compact := app.build(ui2.rect(0, 0, 480, 360))!
	assert compact.children.any(it.id == 'software.cleanup.back') && !compact.children.any(it.id == 'software.cleanup.confirm')
	free_window_tree(compact)
	app.handle(packagecore.request_prefix + '{"id":"editor"}')!
	app.handle('software.install')!; app.paste_input('ignored')
	assert app.launch_request == '' && app.worker == unsafe { nil } && app.cleanup_ready && editor_bytes_text(app.query) == 'editor'
	os.setenv('VINIX_SOFTWARE_CLEANUP_MODE', 'stale', true)
	app.handle('software.cleanup.confirm')!
	assert app.admin_prompt && app.worker.args == ['admin', 'cleanup-apply', 'd'.repeat(64)] && !app.cleanup_ready
	app.key_input('fixture secret é'); app.key_input('\r')
	assert !app.admin_prompt && !app.prepare_close() && app.admin_password.all(it == 0)
	app.handle('software.cleanup.back')!; assert app.cleanup_mode
	wait_for_software(mut app)
	assert !app.cleanup_ready && app.cleanup_snapshot.generations.len == 0 && app.failure_pages.len > 0 && app.status.contains('stale')
	assert !os.exists(receipt)
	app.handle('software.cleanup.confirm')!; assert app.worker == unsafe { nil }
	os.unsetenv('VINIX_SOFTWARE_CLEANUP_MODE')
	app.handle('software.cleanup.reload')!; wait_for_software(mut app)
	assert app.cleanup_ready
	app.handle('software.cleanup.confirm')!; app.key_input('fixture secret é'); app.key_input('\r')
	wait_for_software(mut app)
	assert app.cleanup_mode && app.cleanup_ready && app.cleanup_snapshot.generations.len == 0 && app.status.contains('Cleanup finished')
	assert os.read_file(receipt)! == 'reviewed generations only'
	assert app.filter == 2 && app.selected == 0 && editor_bytes_text(app.query) == 'editor'
	app.handle('software.cleanup.confirm')!; assert app.worker == unsafe { nil }
	app.key_input('\x1b'); assert !app.cleanup_mode
	for mode in ['invalid', 'failed'] {
		os.setenv('VINIX_SOFTWARE_CLEANUP_MODE', mode, true)
		app.handle('software.cleanup')!; wait_for_software(mut app)
		assert !app.cleanup_ready
		app.handle('software.cleanup.confirm')!; assert app.worker == unsafe { nil }
		app.handle('software.cleanup.back')!
	}
	os.setenv('VINIX_SOFTWARE_CLEANUP_MODE', 'slow', true)
	app.handle('software.cleanup')!; assert app.prepare_close()
	app.close_app(); assert app.worker == unsafe { nil }
	println('SOFTWARE CLEANUP read-only review, complete paged disclosure, modal/compact controls, frozen administrator approval, stale refusal, diagnostics and reload PASS')
}

fn check_software_cleanup_memory() ! {
	$if !track_heap ? { return error('compile cleanup memory fixture with -d track_heap') }
	$if track_heap ? {
		text := json2.encode(fixture_cleanup_review())
		mut app := SoftwareApp{ cleanup_mode: true, output: text.bytes() }
		defer { app.close_app(); unsafe { text.free() } }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.load_cleanup_review(); assert app.cleanup_ready
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
				app.handle_cleanup('software.cleanup.down')
				free_window_tree(app.build(ui2.rect(0, 0, 900, 900))!)
				free_window_tree(app.build(ui2.rect(0, 0, 480, 360))!)
				app.clear_cleanup_review()
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'cleanup view retained ${kept} bytes'
		println('SOFTWARE CLEANUP 1000 owned decode/page/render/compact/retirement cycles retain zero tracked bytes PASS')
	}
}
