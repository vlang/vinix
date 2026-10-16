// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2
import tools.packages.pkgprotocol

fn check_software_release() ! {
	base := os.temp_dir() + '/vinix-software-release-' + os.getpid().str()
	os.mkdir(base)!
	defer { os.rmdir_all(base) or {}; unsafe { base.free() } }
	path := base + '/release apps ; $literal.json'
	defer { unsafe { path.free() } }
	mut app := SoftwareApp{ service_path: os.executable(), release_deployment_path: path.clone(), output: []u8{cap: 8192} }
	defer { app.close_app() }
	app.handle('software.deployment')!
	assert !app.release_deployment_available
	mut tree := app.build(ui2.rect(0, 0, 640, 610))!
	assert !tree.children.any(it.id == 'software.deployment.release')
	free_window_tree(tree)
	app.focus = true; app.deployment_paste_input('/kept manual draft.json')
	app.handle('software.deployment.release')!
	assert app.worker == unsafe { nil } && app.review == '' && app.status.contains('unavailable')
	assert editor_bytes_text(app.deployment_path) == '/kept manual draft.json'
	os.write_file(path, '{"format":1,"architecture":"aarch64","packages":["editor"]}\n')!
	app.handle('software.deployment.back')!; app.handle('software.deployment')!
	assert app.release_deployment_available
	tree = app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.id == 'software.deployment.release' && it.text == 'Review release apps')
	assert !tree.children.any(it.id == 'software.confirm')
	free_window_tree(tree)
	// The old picker cannot redirect the new read-only proposal.
	app.deployment_choice_pending = true; app.deployment_choice_current = true
	app.handle('software.deployment.release')!
	assert app.worker_review && app.deployment_pending == path && !app.review_ready
	assert app.prepare_close() && !app.admin_prompt && !app.deployment_choice_current
	assert app.finish_deployment_choice('/late choice.json') && app.deployment_pending == path
	app.handle('software.confirm')!
	wait_for_software(mut app)
	assert app.review_ready && app.review_snapshot.operation == 'deploy' && app.deployment_pending == path
	assert app.review_snapshot.rows.len == 2 && app.review_snapshot.rows.any(it.kind == 'runtime')
	software_repository_text(mut app.deployment_path, '/changed form.json')
	assert app.deployment_pending == path
	tree = app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.id == 'software.confirm')
	free_window_tree(tree)
	app.handle('software.cancel')!
	app.handle('software.deployment.release')!
	wait_for_software(mut app)
	assert app.deployment_pending == path
	app.handle('software.cancel')!
	os.rm(path)!
	software_repository_text(mut app.deployment_path, '/kept draft.json')
	app.handle('software.deployment.release')!
	assert !app.release_deployment_available && app.worker == unsafe { nil } && editor_bytes_text(app.deployment_path) == '/kept draft.json'
	os.write_file(base + '/other.json', '{}')!; os.symlink(base + '/other.json', path)!
	app.handle('software.deployment.back')!; app.handle('software.deployment')!
	assert !app.release_deployment_available
	assert SoftwareApp{}.release_deployment_path == pkgprotocol.image_applications_path
	println('Software release catalog: optional ordinary-file discovery, explicit full-closure review, frozen literal path, separate confirmation, stale-picker retirement, missing/link refusal and retained drafts PASS')
}

fn check_software_release_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut app := SoftwareApp{ deployment_mode: true, release_deployment_available: true }
		app.initialize_deployment_field()
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
				free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				app.handle('software.deployment.back')!
				app.handle('software.deployment')!
				app.handle('software.deployment.release')!
				app.release_deployment_available = true
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'release catalog form retained ${kept} bytes'
		println('Software release catalog: 1000 full/compact form, discovery, missing-file refusal, navigation and retirement cycles retain zero tracked bytes PASS')
	}
}
