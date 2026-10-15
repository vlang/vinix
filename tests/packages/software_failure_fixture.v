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
	return software_failure_fixture_join_pages(app.failure_pages)
}

fn software_failure_fixture_join_pages(pages []SoftwareFailurePage) string {
	mut bytes := []u8{cap: software_failure_limit * 4}
	defer { unsafe { bytes.free() } }
	for page in pages {
		for byte in page.text { if byte != `\n` { bytes << byte } }
	}
	return bytes.bytestr()
}

fn check_software_failure_compact() ! {
	mut app := SoftwareApp{ output: []u8{cap: 8192}, query: 'kept catalog'.bytes(),
		matching: [0], selected: 0, filter: 1, deployment_mode: true,
		rows: [SoftwareRow{ id: 'editor', installed_version: '1.0.0' }] }
	defer { app.close_app() }
	text := software_failure_fixture_text() + 'Wide glyphs: ' + 'M'.repeat(80) + '\nControls: \x1b\xff\xc2\x80\n'
	defer { unsafe { text.free() } }
	for byte in text { app.output << byte }
	app.capture_failure(['deployment-review', '/literal é; $file'], 27)
	full_text := software_failure_fixture_join_pages(app.failure_pages)
	compact_text := software_failure_fixture_join_pages(app.failure_compact_pages)
	assert full_text == compact_text && app.failure_compact_pages.len > app.failure_pages.len
	unsafe { full_text.free(); compact_text.free() }
	for page in app.failure_compact_pages {
		mut lines := page.text.split('\n')
		assert lines.len <= 3 && page.source_page >= 0 && page.source_page < app.failure_pages.len
		for line in lines { assert line.len <= 12 && utf8.validate_str(line) }
		software_policy_free_lines(mut lines)
	}
	app.handle('software.failure')!; assert app.failure_mode
	// Traverse every short page through the actual view and navigation handlers.
	for index in 0 .. app.failure_compact_pages.len {
		tree := app.build(ui2.rect(0, 0, 320, 240))!
		assert app.failure_compact_mode && app.failure_compact_page == index
		assert app.failure_page == app.failure_compact_pages[index].source_page
		assert tree.children.any(it.id == 'software.failure.back') && tree.children.any(it.id == 'software.failure.previous')
		assert tree.children.any(it.id == 'software.failure.next') && tree.children.any(it.text == app.failure_compact_pages[index].label)
		mut visible := []u8{cap: 48}
		for element in tree.children {
			assert element.frame.x >= 0 && element.frame.x + element.frame.width <= 320
			assert element.frame.y >= 0 && element.frame.y + element.frame.height <= 240
			if element.text_style.font_family == 'mono' {
				assert !element.text.contains('\n') && utf8.validate_str(element.text)
				for byte in element.text { visible << byte }
			}
		}
		expected := app.failure_compact_pages[index].text.replace('\n', '')
		assert editor_bytes_text(visible) == expected
		unsafe { visible.free(); expected.free() }
		free_window_tree(tree)
		if index % 2 == 0 { app.key_input('\x1b[C') } else { app.key_input('\x1b[6~') }
	}
	assert app.failure_compact_page == app.failure_compact_pages.len - 1
	for _ in 0 .. app.failure_compact_pages.len + 2 { app.key_input('\x1b[5~') }
	assert app.failure_compact_page == 0 && app.failure_page == 0
	for _ in 0 .. 5 { app.key_input('\x1b[C') }
	short_page := app.failure_compact_page; canonical := app.failure_page
	assert short_page > 0
	for size in [ui2.rect(0, 0, 900, 660), ui2.rect(0, 0, 180, 200), ui2.rect(0, 0, 180, 96), ui2.rect(0, 0, 160, 240), ui2.rect(0, 0, 320, 240)]! {
		tree := app.build(size)!
		assert app.failure_compact_page == short_page && app.failure_page == canonical
		for element in tree.children {
			assert element.frame.x >= 0 && element.frame.x + element.frame.width <= size.width
			assert element.frame.y >= 0 && element.frame.y + element.frame.height <= size.height
			if element.text_style.font_family == 'mono' { assert !element.text.contains('\n') }
			if size.width < 640 && size.height >= 200 && element.text == app.failure_compact_pages[short_page].label {
				assert element.frame.width >= 56
			}
		}
		assert tree.children.any(it.id == 'software.failure.back')
		free_window_tree(tree)
	}
	full := app.build(ui2.rect(0, 0, 640, 610))!
	assert full.children.filter(it.text_style.font_family == 'mono').len <= 14
	assert full.children.filter(it.text_style.font_family == 'mono').len > 3
	free_window_tree(full)
	app.handle('software.failure.next')!; assert app.failure_page == canonical + 1
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	assert app.failure_compact_pages[app.failure_compact_page].source_page == canonical + 1
	assert app.failure_compact_page == 0 || app.failure_compact_pages[app.failure_compact_page - 1].source_page != canonical + 1
	free_window_tree(compact)
	for event in ['software.confirm', 'software.install', 'software.refresh', 'software.snapshot.save', 'software.policy.confirm']! { app.handle(event)! }
	app.key_input('typed'); app.paste_input('\x1b'); app.paste_input('\x1b[C')
	assert app.failure_mode && app.worker == unsafe { nil } && app.query.bytestr() == 'kept catalog'
	assert app.deployment_mode && app.selected == 0 && app.filter == 1 && app.matching == [0]
	app.key_input('\x1b'); assert !app.failure_mode && app.deployment_mode
	app.handle('software.failure')!; app.handle('software.failure.clear')!
	assert !app.failure_mode && app.failure_pages.len == 0 && app.failure_compact_pages.len == 0
	assert app.failure_compact_page == 0 && !app.failure_compact_mode
	println('Software failure navigation: complete short Unicode/escaped diagnostic pages, separate native-renderer lines, Previous/Next/arrow/Page keys, resize anchors, narrow/tiny Back, modal isolation and clear PASS')
}

fn check_software_failure() ! {
	check_software_status_reader()!
	check_software_failure_compact()!
	mut app := SoftwareApp{service_path: os.executable(), output: []u8{cap: 8192}, query: []u8{cap: 256}}
	defer { app.close_app() }
	app.start(['install', 'diagnostic-app'], false)
	app.handle('software.status')!; assert !app.status_reader.mode
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
	for page in app.failure_compact_pages { assert utf8.validate_str(page.text) }
	app.handle('software.failure')!
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	assert compact.children.any(it.text == 'Earlier output omitted.')
	free_window_tree(compact); app.handle('software.failure.back')!
	clean := software_failure_text('é🚀\r\n\t\x1b\x00\x7f\xc2\x80\xff\xe2')
	assert clean == 'é🚀\n \\x1b\\x00\\x7f\\xc2\\x80\\xff\\xe2', clean
	unsafe { clean.free() }
	app.output.clear(); app.output_truncated = true
	app.capture_failure([], 9)
	assert app.failure_truncated && app.failure_pages[0].text.contains('no diagnostic text')
	app.worker_failed = true; app.capture_failure(['view'], 0)
	assert app.failure_heading.contains('response too large')
	app.output.clear()
	for byte in '\n'.repeat(15) { app.output << byte }
	app.capture_failure(['view'], 1)
	for index, _ in app.failure_pages {
		assert app.failure_compact_pages.any(it.source_page == index)
	}
	app.failure_page = app.failure_pages.len - 1
	blank := app.build_failure(ui2.rect(0, 0, 320, 240))
	assert app.failure_compact_pages[app.failure_compact_page].source_page == app.failure_page
	free_window_tree(blank)
	app.operation_output('x'.repeat(pkgprotocol.progress_limit + 1))
	assert app.output_truncated && app.progress_skip
	app.finish_operation_output()
	println('Software failure details: bounded tail, truncation disclosure, valid UTF-8/control escaping, empty diagnostics and response-limit failure passed')
}

fn check_software_failure_memory() ! {
	$if !track_heap ? { return error('compile failure memory fixture with -d track_heap') }
	$if track_heap ? {
		mut app := SoftwareApp{output: []u8{cap: 8192}}
		app.set_status('Local validation: /private/é🚀/a long source path; restore trusted metadata before retrying.\n\x1b\xff')
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
				for _ in 0 .. app.failure_compact_pages.len {
					free_window_tree(app.build_failure(ui2.rect(0, 0, 320, 240)))
					app.key_input('\x1b[6~')
				}
				short_page := app.failure_compact_page; canonical := app.failure_page
				free_window_tree(app.build_failure(ui2.rect(0, 0, 900, 660)))
				free_window_tree(app.build_failure(ui2.rect(0, 0, 180, 200)))
				assert app.failure_compact_page == short_page && app.failure_page == canonical
				app.paste_input('\x1b'); assert app.failure_mode
				app.handle('software.failure.back')!
				app.clear_failure()
				assert app.failure_compact_pages.len == 0 && !app.failure_compact_mode
				status_reader_cycle(mut app)!
			}
		}
		kept := C.vinix_heap_end()
		app.close_app()
		assert kept == 0, 'failure details retained ${kept} bytes'
		println('Software failure details: 1000 capture/full/compact/all-short-pages/keys/resize/back/replace/clear cycles retain zero tracked bytes')
		println('Software status reader: 1000 capture/native-page/keyboard/resize/ignored-write/Back/cache-retirement cycles retain zero tracked bytes')
	}
}

fn status_reader_cycle(mut app SoftwareApp) ! {
	status := app.status; focus := app.focus; selection := app.select_all; query := editor_bytes_text(app.query)
	failure := app.failure_pages.data; heading := app.failure_heading; report := app.details_pages.data
	app.handle('software.status')!; assert app.status_reader.mode && app.status_reader.pages.len > 0
	for size in [ui2.rect(0, 0, 180, 200), ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
		free_window_tree(app.build(size)!)
		app.key_input('\x1b[C')
	}
	free_window_tree(app.build(ui2.rect(0, 0, 180, 200))!)
	for action in ['software.confirm', 'software.cancel', 'software.failure.clear', 'software.report.read', 'software.catalog.filter',
		'software.snapshot.save', 'software.launch.run', 'software.reload', 'software.refresh', 'software.install', 'software.run',
		'software.launch:{"id":"editor"}']! { app.handle(action)! }
	app.key_input('typed'); app.paste_input('\x1b'); app.paste_input('\x1b[C')
	assert app.status_reader.mode && app.worker == unsafe { nil } && !app.admin_prompt && app.launch_request == ''
	assert app.status == status && app.focus == focus && app.select_all == selection && editor_bytes_text(app.query) == query
	assert app.failure_pages.data == failure && app.failure_heading == heading && app.details_pages.data == report
	app.key_input('\x1b')
	assert !app.status_reader.mode && app.status_reader.pages.len == 0 && app.status_reader.short_pages.len == 0
}

fn check_software_status_reader() ! {
	mut app := SoftwareApp{ query: 'kept search'.bytes(), focus: true, select_all: true, filter: 1, selected: 7, scroll: 3,
		output: []u8{cap: 8192}, administration_required: true }
	defer { app.close_app() }
	app.handle('software.status')!; assert !app.status_reader.mode // Empty status has no reader.
	text := 'Local validation: ' + '/private/é🚀; $literal/'.repeat(48) + '\r\n\tControls: \x1b\xff\xc2\x80\nRestore trusted input and retry.'
	defer { unsafe { text.free() } }
	app.set_status(text)
	for byte in 'Retained service failure: previous operation failed.' { app.output << byte }
	app.capture_failure(['view'], 27)
	mut review := fixture_review('install', ['editor'])
	review_text := json2.encode(review); review.close()
	metadata_fixture_review(mut app, 0, review_text); unsafe { review_text.free() }
	app.prepare_package_plan(); app.set_status(text)
	prepared := app.details_pages.data; fingerprint := app.review_snapshot.fingerprint
	for mode in ['catalog', 'repository', 'deployment', 'mirror', 'policy', 'data', 'launch', 'health', 'cleanup', 'audit', 'snapshot', 'browser']! {
		app.repository_mode = mode == 'repository'; app.deployment_mode = mode == 'deployment'; app.mirror_mode = mode == 'mirror'
		app.policy_mode = mode == 'policy'; app.data_mode = mode == 'data'; app.launch_mode = mode == 'launch'
		app.health_mode = mode == 'health'; app.cleanup_mode = mode == 'cleanup'; app.audit_mode = mode == 'audit'
		app.snapshot_mode = mode == 'snapshot'; app.catalog_browser_mode = mode == 'browser'
		mut footer := frame_elements(3)
		app.add_status_footer(mut footer, 640, 610, false)
		assert footer.any(it.id == 'software.status') && footer.any(it.id == 'software.failure')
		free_window_tree(ui2.screen(u32(0), footer))
		status_reader_cycle(mut app)!
		assert app.details_pages.data == prepared && app.review_snapshot.fingerprint == fingerprint && app.review_ready
	}
	app.repository_mode = false; app.deployment_mode = false; app.mirror_mode = false; app.policy_mode = false; app.data_mode = false
	app.launch_mode = false; app.health_mode = false; app.cleanup_mode = false; app.audit_mode = false; app.snapshot_mode = false; app.catalog_browser_mode = false
	app.clear_review(); app.set_status(text)
	for size in [ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 320, 240), ui2.rect(0, 0, 640, 610)]! {
		tree := app.build(size)!
		assert tree.children.any(it.id == 'software.status') && tree.children.any(it.id == 'software.failure')
		free_window_tree(tree)
	}
	app.handle('software.status')!
	full := software_failure_fixture_join_pages(app.status_reader.pages)
	short := software_failure_fixture_join_pages(app.status_reader.short_pages)
	safe := software_failure_text(text); expected := safe.replace('\n', '')
	assert full == expected && short == full && full.contains('\\x1b\\xff\\xc2\\x80')
	unsafe { full.free(); short.free(); safe.free(); expected.free() }
	assert app.status_reader.short_pages.len > app.status_reader.pages.len
	for i in 0 .. app.status_reader.short_pages.len {
		for size in [ui2.rect(0, 0, 180, 200), ui2.rect(0, 0, 320, 240)]! {
			tree := app.build(size)!
			assert app.status_reader.short_page == i && app.status_reader.page == app.status_reader.short_pages[i].source_page
			details_fixture_rendered_lines(&tree, app.status_reader.short_pages[i].text, 14, 110, int(size.width) - 28, 16, 12)
			for element in tree.children {
				assert element.frame.x >= 0 && element.frame.y >= 0 && element.frame.x + element.frame.width <= size.width
				assert element.frame.y + element.frame.height <= size.height
			}
			free_window_tree(tree)
		}
		app.key_input(if i % 2 == 0 { '\x1b[C' } else { '\x1b[6~' })
	}
	last := app.status_reader.short_page; canonical := app.status_reader.page
	app.handle('software.status.next')!; assert app.status_reader.short_page == last
	for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 160, 180), ui2.rect(0, 0, 180, 200)]! {
		free_window_tree(app.build(size)!); assert app.status_reader.short_page == last && app.status_reader.page == canonical
	}
	for _ in 0 .. app.status_reader.short_pages.len + 2 { app.key_input('\x1b[5~') }
	assert app.status_reader.page == 0 && app.status_reader.short_page == 0
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	app.key_input('\x1b[C'); assert app.status_reader.page == 1
	free_window_tree(app.build(ui2.rect(0, 0, 180, 200))!)
	assert app.status_reader.short_pages[app.status_reader.short_page].source_page == 1
	app.handle('software.status.back')!; assert !app.status_reader.mode
	for bounded in ['x'.repeat(8192), 'prefix' + '界'.repeat(2731) + '\xff'] {
		app.set_status(bounded); app.open_status_reader()
		assert app.status_reader.truncated == (bounded.len > 8192)
		start := if bounded.len > 8192 { bounded.len - 8192 } else { 0 }
		escaped := software_failure_text(unsafe { tos(bounded.str + start, bounded.len - start) })
		wanted := escaped.replace('\n', '')
		actual := software_failure_fixture_join_pages(app.status_reader.short_pages)
		assert actual == wanted && app.status_reader.short_pages.len < 1024
		for page in app.status_reader.short_pages { assert utf8.validate_str(page.text) }
		unsafe { escaped.free(); wanted.free(); actual.free() }
		app.handle('software.status.back')!
	}
	app.admin_prompt = true; app.open_status_reader(); assert !app.status_reader.mode; app.admin_prompt = false
	app.window_mode = true; app.open_status_reader(); assert !app.status_reader.mode; app.window_mode = false
	app.failure_mode = true; app.open_status_reader(); assert !app.status_reader.mode; app.failure_mode = false
	app.details_mode = true; app.open_status_reader(); assert !app.status_reader.mode; app.details_mode = false
	app.open_status_reader(); assert app.status_reader.mode // Closing the application also retires a reader left open.
	println('Software status reader: twelve idle contexts, complete Unicode/escaped text, 8192-byte bounds/tail notice, separate failure/report caches, native short lines, modal isolation, resize/keys/Back and worker admission passed')
}
