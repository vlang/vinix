// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import json2
import os
import ui2
import tools.packages.pkgprotocol

fn software_failure_fixture_text() string {
	return 'FIRST CAUSE: authenticated object could not be verified.\n'
		+ '/repository/' + 'a long Unicode path é🚀; $literal/'.repeat(45) + '\n'
		+ 'Context line\n'.repeat(25) + 'LAST ACTION: restore the trusted source and retry.\n'
}

fn software_failure_service_fixture(args []string) bool {
	if args.len != 3 || args[1] != 'install' || args[2] != 'diagnostic-app' { return false }
	println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{phase: 'verify', package: 'diagnostic-app', path: 'bin/app'}))
	print(software_failure_fixture_text())
	exit(27)
	return true
}

fn software_failure_fixture_join(app &SoftwareApp) string {
	mut text := ''
	for page in app.failure_pages {
		next := text + page.text
		unsafe { text.free() }
		text = next
	}
	return text.replace('\n', '')
}

fn check_software_failure() ! {
	mut app := SoftwareApp{service_path: os.executable(), output: []u8{cap: 8192}, query: []u8{cap: 256}}
	defer { app.close_app() }
	app.start(['install', 'diagnostic-app'], false)
	app.handle('software.failure')!
	assert !app.failure_mode
	wait_for_software(mut app)
	assert app.failure_pages.len > 3 && !app.failure_truncated
	assert app.failure_heading == 'Install software · exit 27'
	assert !app.status.contains('FIRST CAUSE') && app.status.contains('LAST ACTION')
	joined := software_failure_fixture_join(&app)
	expected := software_failure_fixture_text().replace('\n', '')
	assert joined == expected && !joined.contains(pkgprotocol.progress_prefix)
	unsafe { joined.free(); expected.free() }
	tree := app.build(ui2.rect(0, 0, 640, 610))!
	assert tree.children.any(it.id == 'software.failure')
	free_window_tree(tree)
	app.handle('software.failure')!
	assert app.failure_mode && app.failure_page == 0
	app.handle('software.failure.previous')!
	assert app.failure_page == 0
	for _ in 0 .. app.failure_pages.len + 2 { app.handle('software.failure.next')! }
	assert app.failure_page == app.failure_pages.len - 1
	page := app.build(ui2.rect(0, 0, 640, 610))!
	assert page.children.any(it.id == 'software.failure.back')
	assert !page.children.any(it.id == 'software.confirm' || it.id == 'software.install')
	free_window_tree(page)
	for action in ['software.confirm', 'software.remove', 'software.refresh', 'software.reload', 'software.failure'] { app.handle(action)! }
	app.key_input('typed text'); app.paste_input('pasted text')
	assert app.worker == unsafe { nil } && app.failure_mode && app.query.len == 0
	small := app.build(ui2.rect(0, 0, 320, 240))!
	assert small.children.any(it.id == 'software.failure.back')
	free_window_tree(small)
	app.key_input('\x1b')
	assert !app.failure_mode && app.failure_pages.len > 0
	app.start(['view'], true)
	wait_for_software(mut app)
	assert app.failure_heading == 'Install software · exit 27' && app.failure_pages.len > 3
	// The same retained failure is reachable from administrative and launch forms.
	for mode in ['repository', 'deployment', 'mirror', 'policy', 'data', 'launch'] {
		app.repository_mode = mode == 'repository'; app.deployment_mode = mode == 'deployment'
		app.mirror_mode = mode == 'mirror'; app.policy_mode = mode == 'policy'
		app.data_mode = mode == 'data'; app.launch_mode = mode == 'launch'
		mut children := frame_elements(2)
		app.add_status_footer(mut children, 640, 610, false)
		assert children.any(it.id == 'software.failure')
		free_window_tree(ui2.screen(u32(0), children))
		app.handle('software.failure')!
		assert app.failure_mode
		app.handle('software.failure.back')!
		assert !app.failure_mode && app.worker == unsafe { nil }
	}
	app.repository_mode = false; app.deployment_mode = false; app.mirror_mode = false
	app.policy_mode = false; app.data_mode = false; app.launch_mode = false
	app.output.clear()
	for byte in 'second failure' { app.output << byte }
	app.capture_failure(['admin', '--progress', 'repo-apply'], 19)
	assert app.failure_heading == 'Repository administration · exit 19' && app.failure_pages.len == 1
	app.handle('software.failure')!; app.handle('software.failure.clear')!
	assert !app.failure_mode && app.failure_pages.len == 0 && app.failure_heading == ''
	println('Software failure details: complete retained Unicode output, progress filtering, paging, read-only modal, compact back, reload retention and replacement/clear passed')
}

fn check_software_failure_bounds() ! {
	mut app := SoftwareApp{output: []u8{cap: 20000}}
	defer { app.close_app() }
	for byte in 'discarded prefix'.repeat(1000) + 'é🚀'.repeat(1400) { app.output << byte }
	app.capture_failure(['view'], 1)
	assert app.failure_truncated && app.failure_pages.len > 0
	for page in app.failure_pages { assert utf8.validate_str(page.text) }
	clean := software_failure_text('é🚀\r\n\t\x1b\x00\x7f\xc2\x80\xff\xe2')
	assert clean == 'é🚀\n \\x1b\\x00\\x7f\\xc2\\x80\\xff\\xe2', clean
	unsafe { clean.free() }
	app.output.clear(); app.output_truncated = true
	app.capture_failure([], 9)
	assert app.failure_truncated && app.failure_pages[0].text.contains('no diagnostic text')
	app.worker_failed = true; app.capture_failure(['view'], 0)
	assert app.failure_heading.contains('response too large')
	app.operation_output('x'.repeat(pkgprotocol.progress_limit + 1))
	assert app.output_truncated && app.progress_skip
	app.finish_operation_output()
	println('Software failure details: bounded tail, truncation disclosure, valid UTF-8/control escaping, empty diagnostics and response-limit failure passed')
}

fn check_software_failure_memory() ! {
	$if !track_heap ? { return error('compile failure memory fixture with -d track_heap') }
	$if track_heap ? {
		mut app := SoftwareApp{output: []u8{cap: 8192}}
		for byte in 'Cause: é🚀 long path and escaped controls\x1b\xff\n'.repeat(20) { app.output << byte }
		arguments := ['install', 'diagnostic-app']
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				app.capture_failure(arguments, 27)
				app.handle('software.failure')!
				free_window_tree(app.build_failure(ui2.rect(0, 0, 640, 610)))
				app.handle('software.failure.next')!
				free_window_tree(app.build_failure(ui2.rect(0, 0, 640, 610)))
				app.handle('software.failure.previous')!
				app.handle('software.failure.back')!
				app.clear_failure()
			}
		}
		kept := C.vinix_heap_end()
		app.close_app()
		assert kept == 0, 'failure details retained ${kept} bytes'
		println('Software failure details: 1000 capture/page/render/back/replace/clear cycles retain zero tracked bytes')
	}
}
