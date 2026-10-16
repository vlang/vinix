// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import ui2

fn deployment_form_geometry(tree ui2.Element, width f64, height f64) {
	for child in tree.children {
		assert child.frame.x >= 0 && child.frame.y >= 0 && child.frame.width > 0 && child.frame.height > 0
		assert child.frame.x + child.frame.width <= width && child.frame.y + child.frame.height <= height
		deployment_form_geometry(child, child.frame.width, child.frame.height)
	}
}

fn deployment_form_select(mut app SoftwareApp, id string) ! {
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	for _ in 0 .. 8 { app.handle('software.deployment.action.previous')! }
	for _ in 0 .. 8 {
		tree := app.build(ui2.rect(0, 0, 320, 240))!
		found := tree.children.any(it.id == id)
		free_window_tree(tree)
		if found { app.handle(id)!; return }
		app.handle('software.deployment.action.next')!
	}
	return error('missing compact deployment action: ' + id)
}

fn check_software_deployment_form() ! {
	base := os.temp_dir() + '/vinix-deployment-form-' + os.getpid().str()
	os.mkdir(base)!
	defer { os.rmdir_all(base) or {}; unsafe { base.free() } }
	path := base + '/release 部署; $literal.json'
	defer { unsafe { path.free() } }
	os.write_file(path, '{}')!
	mut app := SoftwareApp{ service_path: os.executable(), administration_required: true,
		release_deployment_path: path.clone(), query: 'kept search'.bytes(), filter: 1, output: []u8{cap: 8192} }
	defer { app.close_app() }
	app.handle('software.deployment')!
	app.capture_failure(['deployment-review'], 23)
	for size in [ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 639, 609), ui2.rect(0, 0, 640, 240), ui2.rect(0, 0, 320, 610)]! {
		for index in 0 .. 8 {
			app.deployment_action = index
			tree := app.build(size)!
			assert app.deployment_form_compact && tree.children.any(it.id == software_deployment_form_actions[index])
			assert tree.children.any(it.id == 'software.deployment.path') && tree.children.any(it.id == 'software.deployment.back')
			assert !tree.children.any(it.id == 'software.confirm')
			deployment_form_geometry(tree, size.width, size.height)
			for child in tree.children {
				if child.text == software_deployment_form_help[index] {
					text := child.children.map(it.text).join('')
					assert text == software_deployment_form_help[index], 'compact help must be complete without overflow marks'
					unsafe { text.free() }
				}
			}
			free_window_tree(tree)
		}
	}
	app.deployment_action = 0
	app.key_input('\x1b[D'); assert app.deployment_action == 0
	app.key_input('\x1b[C'); assert app.deployment_action == 1
	app.key_input('\x1b[6~'); assert app.deployment_action == 2
	app.key_input('\x1b[5~'); assert app.deployment_action == 1
	app.handle('software.deployment.path')!; app.paste_input(path)
	app.key_input('\x1b[C'); assert app.focus && app.deployment_action == 1 && editor_bytes_text(app.deployment_path) == path
	app.paste_input('\x1b[6~'); assert app.deployment_action == 1 && editor_bytes_text(app.deployment_path) == path
	app.key_input('\x1b'); assert !app.focus && app.deployment_mode
	app.handle('software.confirm')!; assert app.worker == unsafe { nil } && app.review == ''
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	assert !app.deployment_form_compact
	app.key_input('\x1b[C'); assert app.deployment_action == 1
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	// Paging drains a late chooser without changing the draft or launching work.
	app.deployment_choice_pending = true; app.deployment_choice_current = true
	app.deployment_action = 0
	pending := app.build(ui2.rect(0, 0, 320, 240))!
	assert pending.children.any(it.text == 'Choosing file…') && !pending.children.any(it.id == 'software.deployment.choose')
	free_window_tree(pending)
	app.handle('software.deployment.action.next')!
	assert app.finish_deployment_choice('/late-choice.json') && editor_bytes_text(app.deployment_path) == path && app.worker == unsafe { nil }
	app.handle('software.status')!; assert app.status_reader.mode
	app.key_input('\x1b'); assert !app.status_reader.mode && app.deployment_action == 1
	deployment_form_select(mut app, 'software.failure')!; assert app.failure_mode
	app.key_input('\x1b'); assert !app.failure_mode
	deployment_form_select(mut app, 'software.deployment.review')!
	assert app.worker_review && app.deployment_pending == path && !app.admin_prompt
	wait_for_software(mut app); assert app.review_ready
	review := app.build(ui2.rect(0, 0, 320, 240))!
	assert !app.deployment_form_compact && review.children.any(it.id == 'software.cancel')
	assert !review.children.any(it.id == 'software.confirm' || it.id == 'software.deployment.path')
	free_window_tree(review)
	app.handle('software.cancel')!
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	deployment_form_select(mut app, 'software.deployment.audit')!
	wait_for_software(mut app); assert app.audit_ready && !app.admin_prompt
	app.handle('software.audit.back')!
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	deployment_form_select(mut app, 'software.deployment.snapshot')!
	assert app.snapshot_mode && app.worker == unsafe { nil }; app.handle('software.snapshot.back')!
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	deployment_form_select(mut app, 'software.policy')!
	wait_for_software(mut app); assert app.policy_ready && !app.admin_prompt
	app.handle('software.policy.back')!
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	deployment_form_select(mut app, 'software.deployment.release')!
	wait_for_software(mut app); assert app.review_ready && app.deployment_pending == path
	app.handle('software.cancel')!
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	deployment_form_select(mut app, 'software.deployment.release-audit')!
	wait_for_software(mut app); assert app.audit_ready && app.audit_path == path && !app.admin_prompt
	app.handle('software.audit.back')!
	// Optional release/failure actions disappear without stranding selection.
	app.clear_failure(); os.rm(path)!
	app.handle('software.deployment.back')!; app.handle('software.deployment')!
	app.deployment_action = 6
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	assert app.deployment_action == 0
	for _ in 0 .. 12 { app.handle('software.deployment.action.next')! }
	assert app.deployment_action == 4
	app.key_input('\x1b'); assert !app.deployment_mode && app.query.bytestr() == 'kept search' && app.filter == 1
	println('Software compact deployment: complete bounded help and controls at 320x240, literal editing, keyboard/pager/resize anchors, optional actions, stale chooser, status/failure, review/audit/snapshot/policy/release routing and separate confirmation PASS')
}

fn check_software_deployment_form_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut app := SoftwareApp{ deployment_mode: true, release_deployment_available: true }
		app.initialize_deployment_field()
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for index in 0 .. 7 {
					app.deployment_action = index
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					app.key_input('\x1b[C'); app.key_input('\x1b[D')
					app.handle('software.deployment.path')!; app.paste_input('/literal 部署; $file.json')
					app.key_input('\x01'); app.paste_input('bad\xff'); app.paste_input('')
					app.key_input('\x1b'); app.deployment_path.clear()
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
					free_window_tree(app.build(ui2.rect(0, 0, 319, 239))!)
				}
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'compact deployment form retained ${kept} bytes'
		println('Software compact deployment: 1000 seven-action render/edit/rejected-paste/keyboard/full/compact/tiny/retirement cycles retain zero tracked bytes PASS')
	}
}
