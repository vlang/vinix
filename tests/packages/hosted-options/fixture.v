// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import time
import desktop.packagecore
import tools.packages.pkgprotocol

const hosted_options_text = '--title "λ; $(literal)" "" --file "a space" ">" "$HOME"'
const hosted_options_document = '/private/tmp/a space; $(literal) 文档.txt'

fn hosted_options_require(ok bool, message string) ! { if !ok { return error(message) } }

fn hosted_options_app() SoftwareApp {
	return SoftwareApp{ service_path: '/usr/bin/vinix-package', output: []u8{cap: 8192}, selected: 0,
		rows: [SoftwareRow{ id: 'hosted-app', name: 'Candidate', kind: 'linux', permissions: [],
			installed_name: 'Installed', installed_kind: 'linux', installed_version: '1.0.0',
			installed_permissions: ['display', 'files'] }] }
}

fn hosted_options_draft(mut app SoftwareApp, cwd bool) ! {
	app.open_launch_options()
	hosted_options_require(app.launch_mode && app.launch_hosted_display, 'installed display grant not frozen')!
	app.launch_focus = 1; app.paste_input(hosted_options_text)
	app.launch_focus = 2; app.paste_input(hosted_options_document); app.add_launch_file()
	app.launch_data_cwd = cwd
	hosted_options_require(app.launch_documents == [hosted_options_document], 'literal file grant changed')!
}

fn hosted_options_expected(cwd bool, terminal bool) ![]string {
	mut vector := []string{cap: 16}
	unsafe { vector.flags |= .noslices }
	vector << if terminal { 'run-terminal-args'.clone() } else { 'run-args'.clone() }
	vector << 'hosted-app'.clone()
	if cwd { vector << '--data-cwd'.clone() }
	for value in ['--file', hosted_options_document, '--', '--title', 'λ; $(literal)', '', '--file', 'a space', '>', '$HOME']! {
		vector << value.clone()
	}
	return vector
}

fn hosted_options_functional() ! {
	for cwd in [false, true]! {
		mut app := hosted_options_app()
		defer { app.close_app() }
		hosted_options_draft(mut app, cwd)!
		// Retargeting presentation cannot change the already opened draft.
		app.selected = -1
		unsafe { app.rows[0].installed_permissions.free() }
		app.rows[0] = SoftwareRow{ ...app.rows[0], installed_permissions: []string{} }
		app.launch_with_options(false)
		mut expected := hosted_options_expected(cwd, false)!
		defer { pkgprotocol.free_command_values(mut expected) }
		hosted_options_require(app.hosted_app != unsafe { nil } && app.worker == unsafe { nil }
			&& !app.launch_mode && !app.launch_hosted_display, 'custom display launch bypassed helper or retained draft')!
		hosted_options_require(app.hosted_app.command == '/usr/bin/vinix-package' && app.hosted_app.argv == expected
			&& app.hosted_app.package_session && app.hosted_app.width == 1024 && app.hosted_app.height == 768,
			'hosted boundary changed literal vector/service/session/geometry')!
		before := hosted_options_calls
		app.handle('software.launch.run')!
		hosted_options_require(hosted_options_calls == before && app.hosted_app.argv == expected, 'hosted navigation admitted another launch')!
		app.close_hosted_package()
		hosted_options_require(app.hosted_app == unsafe { nil }, 'hosted close retained app')!
	}
	mut ordinary := hosted_options_app()
	defer { ordinary.close_app() }
	ordinary.open_hosted_package(packagecore.Request{ id: 'hosted-app', document: hosted_options_document })!
	hosted_options_require(ordinary.hosted_app.argv == ['run', 'hosted-app', hosted_options_document], 'ordinary Run changed vector')!
	ordinary.close_hosted_package()
	for protocol in [1, 2, 3]! {
		ordinary.rows[0] = SoftwareRow{ ...ordinary.rows[0], installed_window_protocol: protocol }
		ordinary.open_launch_options()
		hosted_options_require(!ordinary.launch_mode, 'injected native-window Launch options admitted')!
	}
	unsafe { ordinary.rows[0].installed_permissions.free() }
	ordinary.rows[0] = SoftwareRow{ ...ordinary.rows[0], installed_window_protocol: 0,
		installed_permissions: []string{}, permissions: ['display'] }
	ordinary.open_launch_options()
	hosted_options_require(ordinary.launch_mode && !ordinary.launch_hosted_display, 'candidate display permission selected hosted launch')!
	ordinary.clear_launch_options()
	ordinary.rows[0] = SoftwareRow{ ...ordinary.rows[0], installed_kind: '' }
	ordinary.open_launch_options()
	hosted_options_require(!ordinary.launch_hosted_display, 'legacy presentation used candidate display permission')!
	ordinary.clear_launch_options()
	println('HOSTED OPTIONS frozen installed display, native refusal and literal vector PASS')
}

fn hosted_options_refusals() ! {
	for gate in 0 .. 6 {
		mut app := hosted_options_app()
		hosted_options_draft(mut app, true)!
		mut busy := os.Process{}
		match gate {
			0 { hosted_options_uid = 0 }
			1 { app.service_path = '/tmp/foreign-launcher' }
			2 { app.worker = unsafe { &busy } }
			3 { app.hosted_app = &HostedX11App{} }
			4 { app.terminal_app = &TerminalApp{} }
			5 { app.window_mode = true }
			else {}
		}
		before := hosted_options_calls
		app.launch_with_options(false)
		hosted_options_require(hosted_options_calls == before && app.launch_mode && app.launch_hosted_display
			&& editor_bytes_text(app.launch_arguments) == hosted_options_text
			&& app.launch_documents == [hosted_options_document], 'refused launch changed draft or crossed boundary')!
		expected_status := if gate == 0 { 'Open graphical packages from an ordinary account session.' }
			else if gate == 1 { 'Graphical packages require the signed package launcher.' }
			else { 'a software operation is already running' }
		hosted_options_require(app.status == expected_status, 'refusal lacks correct diagnostic')!
		hosted_options_uid = 501
		app.worker = unsafe { nil }; app.window_mode = false
		app.close_app()
	}
	mut invalid := hosted_options_app()
	defer { invalid.close_app() }
	hosted_options_draft(mut invalid, false)!
	invalid.launch_file << '/unsubmitted'.bytes()
	before := hosted_options_calls
	invalid.launch_with_options(false)
	hosted_options_require(hosted_options_calls == before && invalid.launch_mode, 'unsubmitted file launched')!
	invalid.launch_file.clear(); invalid.launch_arguments.clear(); invalid.launch_arguments << '"unfinished'.bytes()
	invalid.launch_with_options(false)
	hosted_options_require(hosted_options_calls == before && invalid.launch_mode, 'malformed quoted input launched')!
	println('HOSTED OPTIONS six admission gates and invalid draft refusal PASS')
}

fn hosted_options_service(args []string) !bool {
	if os.getenv('VINIX_HOSTED_OPTIONS_BATCH') != '1' || args.len < 2 || args[1] != 'run-args' { return false }
	mut expected := hosted_options_expected(false, false)!
	defer { pkgprotocol.free_command_values(mut expected) }
	hosted_options_require(args[1..] == expected, 'batch worker argv changed')!
	println('HOSTED OPTIONS BATCH BARRIER'); flush_stdout()
	mut release := u8(0)
	hosted_options_require(C.read(0, &release, 1) == 1, 'batch release missing')!
	println('HOSTED OPTIONS BATCH COMPLETE')
	return true
}

fn hosted_options_other_paths() ! {
	mut terminal := hosted_options_app()
	defer { terminal.close_app() }
	hosted_options_draft(mut terminal, true)!
	before := hosted_options_calls
	terminal.launch_with_options(true)
	mut expected_terminal := hosted_options_expected(true, true)!
	defer { pkgprotocol.free_command_values(mut expected_terminal) }
	hosted_options_require(terminal.terminal_app != unsafe { nil } && terminal.hosted_app == unsafe { nil }
		&& terminal.worker == unsafe { nil } && !terminal.launch_mode && hosted_options_calls == before,
		'Terminal display launch routed through hosted helper')!
	hosted_options_require(terminal.terminal_app.argv[0] == '/usr/bin/vinix-package'
		&& terminal.terminal_app.argv[1..] == expected_terminal, 'Terminal literal vector changed')!
	mut batch := hosted_options_app()
	defer { batch.close_app() }
	hosted_options_draft(mut batch, false)!
	batch.clear_launch_options()
	unsafe { batch.rows[0].installed_permissions.free() }
	batch.rows[0] = SoftwareRow{ ...batch.rows[0], installed_permissions: ['files'] }
	batch.open_launch_options()
	hosted_options_require(!batch.launch_hosted_display, 'non-display installed manifest selected X11')!
	batch.launch_focus = 1; batch.paste_input(hosted_options_text)
	batch.launch_focus = 2; batch.paste_input(hosted_options_document); batch.add_launch_file()
	batch.launch_data_cwd = false
	batch.service_path = os.executable()
	os.setenv('VINIX_HOSTED_OPTIONS_BATCH', '1', true)
	defer { os.unsetenv('VINIX_HOSTED_OPTIONS_BATCH') }
	batch.launch_with_options(false)
	hosted_options_require(batch.worker != unsafe { nil } && batch.worker_run && batch.hosted_app == unsafe { nil }
		&& hosted_options_calls == before, 'non-display launch lost batch path')!
	for _ in 0 .. 5000 {
		batch.poll()
		if batch.output.len > 0 { break }
		time.sleep(time.millisecond)
	}
	hosted_options_require(batch.worker != unsafe { nil } && unsafe { tos(batch.output.data, batch.output.len) }.contains('HOSTED OPTIONS BATCH BARRIER'), 'batch child did not reach barrier')!
	mut release := u8(1)
	hosted_options_require(C.write(batch.worker.stdio_fd[0], &release, 1) == 1, 'could not release batch child')!
	for _ in 0 .. 5000 {
		batch.poll()
		if batch.worker == unsafe { nil } { break }
		time.sleep(time.millisecond)
	}
	hosted_options_require(batch.worker == unsafe { nil } && !batch.worker_failed
		&& unsafe { tos(batch.output.data, batch.output.len) }.contains('HOSTED OPTIONS BATCH COMPLETE'), 'batch child did not finish/reap')!
	println('HOSTED OPTIONS Terminal vector and real non-display worker barrier PASS')
}

fn hosted_options_memory() ! {
	$if track_heap ? {
		C.vinix_heap_begin()
		positive := unsafe { malloc(37) }
		positive_bytes := C.vinix_heap_end()
		positive_records := C.vinix_heap_count()
		unsafe { free(positive) }
		hosted_options_require(positive_bytes == 37 && positive_records == 1, 'tracker positive control failed')!
		mut app := hosted_options_app()
		defer { app.close_app() }
		for _ in 0 .. 2 { app.open_hosted_package(packagecore.Request{ id: 'hosted-app', document: hosted_options_document })!; app.close_hosted_package() }
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			app.open_hosted_package(packagecore.Request{ id: 'hosted-app', document: hosted_options_document })!
			app.close_hosted_package()
			mut vector := hosted_options_expected(true, false)!
			app.open_hosted_package_command(vector)!
			pkgprotocol.free_command_values(mut vector)
			app.close_hosted_package()
		}
		kept := C.vinix_heap_end(); records := C.vinix_heap_count()
		hosted_options_require(kept == 0 && records == 0, 'hosted caller/capture ownership retained allocations')!
		println('HOSTED OPTIONS 1000 ordinary/custom boundary cycles retain 0 bytes / 0 records PASS')
	}
}

fn check_hosted_options() ! {
	hosted_options_functional()!
	hosted_options_refusals()!
	hosted_options_other_paths()!
	hosted_options_memory()!
	println('HOSTED OPTIONS explicit production-safe checks PASS')
}
