// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import ui2
import desktop.sessioncore
import desktop.sessionipc

fn deployment_choice_request(directory string) ! {
	reply := sessionipc.session_call('take', [])!
	defer { unsafe { reply.free() } }
	fields := sessioncore.fields(reply)!
	assert fields.count == 9 && fields.values[0] == 'action'
	owner := os.getpid().str()
	defer { unsafe { owner.free() } }
	assert fields.values[1] == owner
	expected := ['dialog', software_deployment_dialog_key, '0', 'Choose deployment file', directory, '', '']
	defer { unsafe { (&array(&expected)).free() } }
	for i, value in expected {
		decoded := sessioncore.unfield(fields.values[i + 2])!
		assert decoded.str() == value
	}
}

fn deployment_choice_result(path string) ! {
	owner := os.getpid().str()
	args := [owner, software_deployment_dialog_key, path]
	defer { unsafe { owner.free(); (&array(&args)).free() } }
	assert sessionipc.session_call_ok('dialog.result', args)
}

fn check_software_deployment_chooser(broker_path string) ! {
	base := '/tmp/vinix-deployment-choice-' + os.getpid().str()
	os.mkdir(base)!
	os.chmod(base, 0o700)!
	previous := os.getenv_opt('VINIX_SESSION_RUNTIME')
	os.setenv('VINIX_SESSION_RUNTIME', base, true)
	defer {
		if value := previous { os.setenv('VINIX_SESSION_RUNTIME', value, true); unsafe { value.free() } }
		else { os.unsetenv('VINIX_SESSION_RUNTIME') }
		os.rmdir_all(base) or {}
		unsafe { base.free() }
	}
	mut broker := sessionipc.session_start_broker_at(base, broker_path) or { panic('cannot launch broker') }
	defer {
		if broker > 0 {
			C.kill(broker, C.SIGKILL)
			mut status := 0
			C.waitpid(broker, &status, 0)
		}
		sessionipc.session_close_control()
	}
	mut ready := false
	for _ in 0 .. 200 {
		if sessionipc.session_call_ok('ping', []) { ready = true; break }
		time.sleep(10 * time.millisecond)
	}
	assert ready, 'the actual session broker did not start'
	assert sessionipc.session_call_ok('attach', []) // act as the compositor for dialog results
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192} }
	defer { app.close_app() }
	app.handle('software.deployment')!
	software_repository_text(mut app.deployment_path, '/tmp/kept original.json')
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	app.handle('software.deployment.choose')!
	assert app.deployment_choice_pending && app.deployment_choice_current && !app.focus
	assert app.worker == unsafe { nil } && app.review == '' && app.prepare_close()
	deployment_choice_request('/tmp')!
	app.handle('software.deployment.choose')!
	empty := sessionipc.session_call('take', [])!
	assert empty == 'empty' // repeated clicks cannot allocate another ticket
	unsafe { empty.free() }
	assert !app.poll() && app.deployment_choice_pending
	pending := app.build(ui2.rect(0, 0, 640, 610))!
	assert pending.children.any(it.text == 'Choosing file…')
	assert !pending.children.any(it.id == 'software.deployment.choose' || it.id == 'software.confirm')
	free_window_tree(pending)
	deployment_choice_result(deployment_navigation_path)!
	assert app.poll() && !app.deployment_choice_pending && !app.deployment_choice_current
	assert editor_bytes_text(app.deployment_path) == deployment_navigation_path && app.status.contains(deployment_navigation_path)
	assert app.worker == unsafe { nil } && app.review == '' && !app.review_ready
	// Selection does not review or apply. The ordinary review freezes the exact
	// literal path, including spaces, Unicode and shell metacharacters.
	app.handle('software.deployment.review')!
	assert app.deployment_pending == deployment_navigation_path && app.worker_review
	wait_for_software(mut app)
	assert app.review_ready && app.review_snapshot.operation == 'deploy'
	app.handle('software.cancel')!
	software_repository_text(mut app.deployment_path, deployment_fixture_path)
	for selected in ['', '/tmp/bad\npath', '/tmp/bad\xc2\x80path', '/tmp/bad\xffpath']! {
		app.handle('software.deployment.choose')!
		deployment_choice_request('/private/tmp')!
		deployment_choice_result(selected)!
		assert app.poll() && !app.deployment_choice_pending
		assert editor_bytes_text(app.deployment_path) == deployment_fixture_path && app.worker == unsafe { nil }
		assert app.status.contains('kept intact')
	}
	// A later manual edit, navigation (even away and back) or review wins over
	// a pending chooser. Its response must still be drained for a fresh retry.
	for action in ['edit', 'back', 'review', 'audit', 'snapshot']! {
		software_repository_text(mut app.deployment_path, deployment_fixture_path)
		app.handle('software.deployment.choose')!
		deployment_choice_request('/private/tmp')!
		match action {
			'edit' {
				app.handle('software.deployment.path')!
				app.key_input('\x01'); app.paste_input('/manual edited.json')
			}
			'back' { app.handle('software.deployment.back')!; app.handle('software.deployment')! }
			'review' { app.handle('software.deployment.review')! }
			'audit' { app.handle('software.deployment.audit')! }
			else { app.handle('software.deployment.snapshot')! }
		}
		assert !app.deployment_choice_current
		before := editor_bytes_text(app.deployment_path).clone()
		status := app.status.clone()
		defer { unsafe { before.free(); status.free() } }
		deployment_choice_result('/late result.json')!
		assert app.poll_deployment_choice() && editor_bytes_text(app.deployment_path) == before && app.status == status
		assert !app.deployment_choice_pending && !app.finish_deployment_choice('/duplicate result.json')
		if app.worker != unsafe { nil } { wait_for_software(mut app) }
		app.clear_review(); app.clear_deployment_audit(); app.clear_deployment_snapshot()
		app.deployment_mode = true
	}
	// Actual broker failure has a bounded fallback, without losing the draft.
	software_repository_text(mut app.deployment_path, deployment_fixture_path)
	app.handle('software.deployment.choose')!
	deployment_choice_request('/private/tmp')!
	C.kill(broker, C.SIGKILL)
	mut broker_status := 0
	assert C.waitpid(broker, &broker_status, 0) == broker
	broker = 0
	assert app.poll() && !app.deployment_choice_pending && app.status.contains('kept intact')
	app.handle('software.deployment.choose')!
	assert !app.deployment_choice_pending && app.status.contains('unavailable') && app.status.contains('absolute')
	assert editor_bytes_text(app.deployment_path) == deployment_fixture_path && app.worker == unsafe { nil }
	println('Software deployment chooser: real broker requests/pending/results/cancel/disconnect, literal paths, explicit review, duplicate suppression and late edit/navigation/review/audit/snapshot retirement PASS')
}

fn check_software_deployment_chooser_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut app := SoftwareApp{ deployment_mode: true }
		app.initialize_deployment_field()
		defer { app.close_app() }
		long := '/' + 'a'.repeat(4095)
		oversized := long + 'b'
		defer { unsafe { long.free(); oversized.free() } }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for selected in [deployment_navigation_path, '', 'relative.json', '/bad\npath', '/bad\xc2\x80', '/bad\xff', long, oversized]! {
					app.deployment_choice_pending = true; app.deployment_choice_current = true
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					before := editor_bytes_text(app.deployment_path).clone()
					assert app.finish_deployment_choice(selected)
					if selected == deployment_navigation_path || selected == long { assert editor_bytes_text(app.deployment_path) == selected }
					else { assert editor_bytes_text(app.deployment_path) == before }
					unsafe { before.free() }
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
					app.deployment_choice_pending = true; app.deployment_choice_current = true
					app.handle('software.deployment.back')!; app.handle('software.deployment')!
					app.set_status('keep status')
					assert app.finish_deployment_choice('/late result.json') && app.status == 'keep status'
				}
				for path in [deployment_navigation_path, long, 'relative.json', '']! {
					directory := software_deployment_choice_directory(path, '/home/ordinary')
					assert directory in ['/private/tmp', '/', '/home/ordinary']!
					unsafe { directory.free() }
				}
				fallback := software_deployment_choice_directory('relative', long)
				assert fallback == '/'
				unsafe { fallback.free() }
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end()
		assert kept == 0, 'deployment chooser retained ${kept} bytes'
		println('Software deployment chooser: 1000 literal/empty/invalid/4096-byte/oversize/late-result/directory/full/compact lifecycle cycles retain zero tracked bytes PASS')
	}
}
