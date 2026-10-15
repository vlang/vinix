// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import ui2
import tools.packages.pkgprotocol
import desktop.packagecore

fn package_plan_text(a &SoftwareApp) string {
	mut bytes := []u8{cap: 20000}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	for page in a.details_pages {
		mut lines := page.text.split_into_lines()
		for line in lines {
			start := if line.starts_with('• ') { 4 } else { 2 }
			for index in start .. line.len { bytes << line[index] }
		}
		software_policy_free_lines(mut lines)
	}
	return bytes.bytestr()
}

fn package_plan_cycle(mut app SoftwareApp, exhaustive bool) ! {
	selected := app.review_selected; scroll := app.review_scroll; catalog := app.selected
	status := app.status; focused := app.focus; selection := app.select_all
	fingerprint := app.review_snapshot.fingerprint; rows := app.review_snapshot.rows.data
	names := app.review_snapshot.names.data; intent := app.review_names.data; path := app.deployment_pending
	for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
		tree := app.build(size)!; assert tree.children.any(it.id == 'software.report.read'); free_window_tree(tree)
	}
	app.handle('software.report.read')!; assert app.report_reader_mode && !app.details_mode
	if exhaustive {
		for canonical, full in app.details_pages {
			mut bytes := []u8{cap: full.text.len}
			for short in app.details_compact_pages {
				if short.source_page == canonical { for byte in short.text { if byte != `\n` { bytes << byte } } }
			}
			expected := full.text.replace('\n', '')
			assert editor_bytes_text(bytes) == expected
			unsafe { bytes.free(); expected.free() }
		}
		for index, short in app.details_compact_pages {
			app.details_compact_page = index; app.details_page = short.source_page
			for size in [ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 320, 240)]! {
				tree := app.build(size)!
				details_fixture_rendered_lines(&tree, short.text, 14, 118, int(size.width) - 28, 18, 12)
				assert tree.children.any(it.id == 'software.report.back') && tree.children.any(it.text == short.label)
				assert !tree.children.any(it.id in ['software.confirm', 'software.cancel', 'software.details', 'software.failure'])
				for element in tree.children {
					assert element.frame.x >= 0 && element.frame.x + element.frame.width <= size.width
					assert element.frame.y >= 0 && element.frame.y + element.frame.height <= size.height
				}
				free_window_tree(tree)
			}
			app.key_input('\x1b[C'); assert app.details_compact_page == if index + 1 < app.details_compact_pages.len { index + 1 } else { index }
		}
		app.key_input('\x1b[5~'); assert app.details_compact_page == app.details_compact_pages.len - 2
		for app.details_compact_page > 0 { app.key_input('\x1b[D') }
		app.key_input('\x1b[D'); assert app.details_compact_page == 0
	}
	free_window_tree(app.build(ui2.rect(0, 0, 180, 220))!); app.key_input('\x1b[6~')
	anchor := app.details_compact_page; canonical := app.details_page
	for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 160, 96), ui2.rect(0, 0, 180, 220)]! {
		tree := app.build(size)!; assert tree.children.any(it.id == 'software.report.back')
		if size.width >= 640 { details_fixture_rendered_lines(&tree, app.details_pages[canonical].text, 14, 94, 612, 20, 52) }
		free_window_tree(tree); assert app.details_page == canonical && app.details_compact_page == anchor
	}
	request := packagecore.request_prefix + '{"id":"editor"}'
	defer { unsafe { request.free() } }
	for action in ['software.confirm', 'software.cancel', 'software.row.1', 'software.up', 'software.down', 'software.details',
		'software.reload', 'software.refresh', 'software.install', 'software.remove', 'software.upgrade', 'software.rollback', 'software.repair',
		'software.search', 'software.run', 'software.deployment.path', 'software.deployment.review', 'software.deployment.back',
		'software.deployment.stop', 'software.review.stop', 'software.failure', 'software.report.read', request]! { app.handle(action)! }
	app.key_input('typed'); app.key_input('\r'); app.key_input('\x01'); app.key_input('\x08'); app.paste_input('changed'); app.paste_input('\x1b')
	assert app.report_reader_mode && app.worker == unsafe { nil } && !app.admin_prompt && app.launch_request == ''
	assert app.review_selected == selected && app.review_scroll == scroll && app.selected == catalog
	assert app.status == status && app.focus == focused && app.select_all == selection
	assert app.review_snapshot.fingerprint == fingerprint && app.review_snapshot.rows.data == rows
	assert app.review_snapshot.names.data == names && app.review_names.data == intent && app.deployment_pending == path
	app.key_input('\t'); app.key_input('\x1b[Z')
	app.key_input('\x1b'); assert !app.report_reader_mode && app.review_ready && app.details_pages.len == 0 && app.details_compact_pages.len == 0
	assert app.review_selected == selected && app.review_scroll == scroll && app.review_read_item == -1
}

fn check_package_plan_boundaries() ! {
	padding := '文'.repeat(1363); path := '/media/' + padding
	description := 'é'.repeat(2048)
	defer { unsafe { padding.free(); path.free(); description.free() } }
	for operation in ['install', 'remove', 'upgrade', 'repair', 'rollback', 'deploy']! {
		for arch in ['aarch64', 'x86_64']! {
			base := if operation == 'deploy' { deployment_navigation_review(false) } else {
				package_navigation_review(operation, if operation in ['install', 'remove']! { ['editor'] } else { []string{} }) }
			mut projected := base.rows.map(pkgprotocol.ReviewPackage{ ...it, architecture: arch })
			unsafe { projected[0].description.free() }
			projected[0] = pkgprotocol.ReviewPackage{ ...projected[0], description: description.clone() }
			unsafe { (&array(&base.rows)).free() }
			mut review := pkgprotocol.Review{ ...base, architecture: arch, rows: projected,
				generation: ~u64(0), disk_needed: ~u64(0), disk_available: ~u64(0), disk_reserve: ~u64(0) }
			review.validate()!
			encoded := json2.encode(review)
			mut app := SoftwareApp{ output: encoded.bytes(), review: operation.clone(), deployment_mode: operation == 'deploy',
				deployment_pending: if operation == 'deploy' { path.clone() } else { '' } }
			for name in review.names { app.review_names << name.clone() }
			review.close(); unsafe { encoded.free() }
			app.load_review(); assert app.review_ready
			package_plan_cycle(mut app, true)!
			app.handle('software.report.read')!
			text := package_plan_text(&app)
			assert text.contains('Operation: ' + operation) && text.contains('Target architecture: ' + arch)
			assert text.contains('Active generation: 18446744073709551615') && text.contains('Review fingerprint: ')
			for label in ['Required disk space', 'Available disk space', 'Reserved disk space']! { assert text.contains(label + ' (bytes): 18446744073709551615') }
			assert text.contains(description) && text.contains('Publisher key:') && text.contains('Displayed package permission: files')
			if operation == 'deploy' { assert text.contains('Frozen deployment file: ' + path) && text.contains('replaces the installed application set') }
			if operation == 'repair' { assert text.contains('Package action: repair') && text.contains('preserves installed versions') }
			if operation == 'remove' { assert text.contains('Package action: remove') && text.contains('Personal application data stays on disk') }
			if operation == 'rollback' { assert text.contains('Restore from generation: 2') && text.contains('new generation') }
			unsafe { text.free() }
			for app.review_read_item > 0 { app.key_input('\x1b[A') }
			app.key_input('\x1b[A'); assert app.review_read_item == 0
			for index in 0 .. app.review_snapshot.names.len + app.review_snapshot.rows.len {
				assert app.review_read_item == index
				current := package_plan_text(&app)
				if index < app.review_snapshot.names.len { assert current.contains('Frozen operation argument: ' + app.review_snapshot.names[index]) }
				else {
					row := app.review_snapshot.rows[index - app.review_snapshot.names.len]
					assert current.contains('Package ID: ' + row.id)
					if row.kind == 'runtime' { assert current.contains('Proprietary payload: Yes') && current.contains('Firmware payload: Yes') }
				}
				unsafe { current.free() }; app.key_input('\x1b[B')
				assert app.review_read_item == if index + 1 < app.review_snapshot.names.len + app.review_snapshot.rows.len { index + 1 } else { index }
			}
			app.handle('software.report.back')!; assert !app.report_reader_mode && app.review_selected == 0
			app.handle('software.cancel')!; app.handle('software.report.read')!; assert !app.report_reader_mode && app.details_pages.len == 0
			app.close_app()
		}
	}
	// A removal-only or empty deployment still has an explicit plan overview.
	mut empty := SoftwareApp{ deployment_mode: true, review: 'deploy'.clone(), deployment_pending: path.clone(), review_ready: true,
		review_snapshot: pkgprotocol.Review{ format: 1, operation: 'deploy'.clone(), architecture: 'aarch64'.clone(), fingerprint: 'c'.repeat(64) } }
	package_plan_cycle(mut empty, true)!
	empty.handle('software.report.read')!; assert !empty.report_has_packages()
	txt := package_plan_text(&empty); assert txt.contains('Packages including dependencies and removals: 0') && txt.contains('empty plan')
	unsafe { txt.free() }; empty.key_input('\t'); assert empty.review_read_item == -1
	empty.key_input('\x1b'); empty.close_app()
	check_package_plan_maximum()!
	println('Software package plan reader: six operations on both architectures, complete metadata and Unicode paths/descriptions, exact u64 space/generations, arguments/packages, empty plans, native lines, resize anchors and frozen confirmation passed')
}

fn check_package_plan_maximum() ! {
	mut names := []string{cap: 4096}; mut requested := []string{cap: 4096}
	mut rows := []pkgprotocol.ReviewPackage{cap: 8192}
	unsafe { names.flags |= .noslices; requested.flags |= .noslices; rows.flags |= .noslices }
	for index in 0 .. 8192 {
		number := index.str(); zeros := '0'.repeat(5 - number.len); id := 'p' + zeros + number
		unsafe { number.free(); zeros.free() }
		if index < 4096 { names << id.clone(); requested << id.clone() }
		row := pkgprotocol.ReviewPackage{ id: id, name: id.clone(), version: '1.0.0', architecture: 'aarch64', kind: 'native',
			repository: 'trusted', public_key: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', license: 'MIT', requested: index < 4096, action: 'keep' }
		unsafe { rows.push_many(&row, 1) }
	}
	mut review := pkgprotocol.Review{ format: 1, operation: 'deploy', architecture: 'aarch64', fingerprint: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
		names: names, requested: requested, rows: rows }
	review.validate()!
	encoded := json2.encode(review); review.close()
	mut app := SoftwareApp{ deployment_mode: true, review: 'deploy'.clone(), deployment_pending: '/approved.json'.clone(), output: encoded.bytes() }
	defer { app.close_app(); unsafe { encoded.free() } }
	app.load_review(); assert app.review_ready && app.review_snapshot.rows.len == 8192 && app.review_snapshot.names.len == 4096
	app.handle('software.report.read')!
	for app.review_read_item > 0 { app.key_input('\x1b[A') }
	for index in 0 .. 12288 {
		assert app.review_read_item == index
		assert app.details_pages.len < 16 // only the current argument/package is cached
		text := package_plan_text(&app)
		expected := if index < 4096 { 'Frozen operation argument: ' + app.review_snapshot.names[index] }
			else { 'Package ID: ' + app.review_snapshot.rows[index - 4096].id }
		assert text.contains(expected)
		unsafe { text.free(); expected.free() }
		app.key_input('\t')
	}
	assert app.review_read_item == 12287 && app.review_selected == 0 && app.review_scroll == 0
	app.key_input('\x1b')
	// Invalid presentation bytes get a diagnostic and never enter pagination.
	mut broken := app.review_snapshot.rows.clone()
	// Move the decoded row fields into the replacement container.
	unsafe { (&array(&app.review_snapshot.rows)).free(); broken[0].description.free() }
	broken[0] = pkgprotocol.ReviewPackage{ ...broken[0], description: '\xff'.clone() }
	app.review_snapshot = pkgprotocol.Review{ ...app.review_snapshot, rows: broken }
	app.handle('software.report.read')!
	invalid := package_plan_text(&app); assert invalid.contains('invalid UTF-8 or oversized metadata') && !app.details_mode
	unsafe { invalid.free() }; app.key_input('\x1b')
	println('Software package plan reader: all 4096 arguments and 8192 packages, bounded per-item caches and invalid-metadata diagnostics passed')
}

const package_navigation_operations = ['install', 'remove', 'upgrade', 'repair', 'rollback']!

fn package_navigation_review(operation string, names []string) pkgprotocol.Review {
	base := fixture_review(operation, names)
	if operation != 'remove' { return base }
	rows := base.rows.map(pkgprotocol.ReviewPackage{ ...it, requested: false, action: 'remove' })
	// Transfer the row strings and permission arrays into the removal projection.
	unsafe { (&array(&base.rows)).free(); (&array(&base.requested)).free() }
	return pkgprotocol.Review{ ...base, requested: [], rows: rows }
}

fn software_package_navigation_service_fixture(args []string) !bool {
	mode := os.getenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION')
	if mode == '' || args.len < 2 { return false }
	if mode.starts_with('review-') && args[1] == 'review' {
		assert args[2] in package_navigation_operations
		text := json2.encode(package_navigation_review(args[2], args[3..]))
		partial := mode == 'review-partial'
		print(if partial { text[..text.len / 2] } else { text }); flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1
		if partial { print(text[text.len / 2..]) }
		return true
	}
	if mode.starts_with('apply-') && args[1] == 'apply' {
		assert os.args[1] == '--progress' && args[2] == 'c'.repeat(64) && args[3] in package_navigation_operations
		assert args[4..] == if args[3] in ['install', 'remove']! { ['editor'] } else { []string{} }
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'stage', current: 1, total: 2 }))
		flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1 && release == `!`
		if mode == 'apply-failed' { eprintln('Package operation was not activated: disk space changed. Review again.'); exit(23) }
		os.write_file(os.getenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION_RECEIPT'), json2.encode(args[2..]))!
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 }))
		return true
	}
	if mode == 'refresh' && args[1] == 'update' {
		println(pkgprotocol.progress_prefix + json2.encode(pkgprotocol.Progress{ phase: 'metadata', repository: 'fixture', path: 'index.json', current: 1 }))
		flush_stdout()
		mut release := u8(0); assert C.read(0, &release, 1) == 1 && release == `!`
		return true
	}
	return false
}

fn seed_package_navigation_catalog(mut app SoftwareApp) {
	if app.rows.len != 0 { app.selected = 0; return }
	unsafe { (&array(&app.rows)).free(); (&array(&app.matching)).free() }
	app.rows = [SoftwareRow{ id: 'editor', name: 'Editor', description: 'Write documents', version: '1.0.0', installed_version: '1.0.0',
		architecture: 'aarch64', kind: 'native', repository: 'fixture', public_key: 'a'.repeat(64), license: 'MIT', permissions: ['files'], requested: true }]
	app.matching = [0]; app.selected = 0
}

fn wait_for_package_navigation_output(mut app SoftwareApp, progress bool) {
	for _ in 0 .. 1000 {
		app.poll()
		if (progress && app.progress_seen) || (!progress && app.output.len > 0) { return }
		time.sleep(time.millisecond)
	}
	assert false, 'package fixture did not reach its input barrier'
}

fn check_package_navigation_writer(mut app SoftwareApp) ! {
	pid := app.worker.pid
	check_package_navigation_paste_guard(mut app)
	assert !app.package_review_running() && !app.prepare_close()
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	assert compact.children.any(it.id == 'software.progress') && compact.children.any(it.text == app.status)
	assert !compact.children.any(it.id in ['software.review.stop', 'software.cancel', 'software.reload', 'software.confirm', 'software.report.read'])
	free_window_tree(compact)
	for action in ['software.review.stop', 'software.cancel', 'software.reload', 'software.search']! { app.handle(action)! }
	app.handle('software.report.read')!; assert !app.report_reader_mode && app.worker.pid == pid
	app.handle('software.catalog.browse')!; assert !app.catalog_browser_mode && app.worker.pid == pid
	app.key_input('\x1b'); app.stop_package_review(); app.key_input('must-not-edit')
	assert app.worker.pid == pid && C.kill(pid, 0) == 0 && app.query.bytestr() == 'Editor'
}

fn check_package_navigation_paste_guard(mut app SoftwareApp) {
	pid := if app.worker == unsafe { nil } { 0 } else { app.worker.pid }
	operation := app.review; fingerprint := app.review_snapshot.fingerprint
	focused := app.focus; selected := app.select_all; scroll := app.scroll; row := app.selected
	status := app.status; output_length := app.output.len
	for input in ['\x1b', '\r', '\n', '\x01', '\x08', '\x7f', 'must not edit', '']! {
		app.paste_input(input)
		assert app.query.bytestr() == 'Editor' && app.focus == focused && app.select_all == selected
		assert app.review == operation && app.review_snapshot.fingerprint == fingerprint
		assert app.scroll == scroll && app.selected == row && app.status == status && app.output.len == output_length
		assert if pid == 0 { app.worker == unsafe { nil } } else { app.worker != unsafe { nil } && app.worker.pid == pid && C.kill(pid, 0) == 0 }
	}
}

fn check_software_package_navigation() ! {
	check_package_plan_boundaries()!
	receipt := os.temp_dir() + '/vinix-package-navigation-' + os.getpid().str()
	os.setenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION_RECEIPT', receipt, true)
	defer { os.rm(receipt) or {}; os.unsetenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION_RECEIPT'); os.unsetenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION') }
	mut app := SoftwareApp{ service_path: os.executable(), output: []u8{cap: 8192}, query: 'Editor'.bytes(), filter: 1 }
	seed_package_navigation_catalog(mut app)
	defer { app.close_app() }
	for operation in package_navigation_operations {
		for mode in ['review-partial', 'review-complete']! {
			for action in ['software.review.stop', 'software.cancel', 'escape']! {
				os.setenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION', mode, true)
				app.handle('software.' + operation)!; pid := app.worker.pid
				wait_for_package_navigation_output(mut app, false)
				assert app.package_review_running() && app.prepare_close() && !app.review_ready && !app.admin_prompt
				check_package_navigation_paste_guard(mut app)
				assert app.worker.args == ['review', operation, ...if operation in ['install', 'remove']! { ['editor'] } else { []string{} }]
				for size in [ui2.rect(0, 0, 640, 610), ui2.rect(0, 0, 320, 240)]! {
					tree := app.build(size)!
					assert tree.children.any(it.id == 'software.review.stop') && tree.children.any(it.text == app.status)
					assert !tree.children.any(it.id in ['software.confirm', 'software.cancel', 'software.report.read'])
					free_window_tree(tree)
				}
				app.handle('software.confirm')!; app.handle('software.search')!; app.key_input('must-not-edit')
				app.handle('software.report.read')!; assert !app.report_reader_mode && app.worker.pid == pid && app.details_pages.len == 0
				app.handle('software.catalog.browse')!; assert !app.catalog_browser_mode && app.worker.pid == pid
				assert !os.exists(receipt) && app.query.bytestr() == 'Editor' && !app.focus
				if action == 'escape' { app.key_input('\x1b') } else { app.handle(action)! }
				assert app.worker == unsafe { nil } && C.kill(pid, 0) != 0 && !app.worker_review && !app.review_ready
				assert app.review == '' && app.review_names.len == 0 && app.review_snapshot.fingerprint == '' && app.output.len == 0 && !app.output_truncated && !app.poll()
				assert app.selected == 0 && app.filter == 1 && app.scroll == 0 && app.query.bytestr() == 'Editor' && app.status.contains('review stopped')
				// Retry must obtain a new complete review after the old worker is gone.
				os.unsetenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION')
				app.handle('software.' + operation)!; wait_for_software(mut app)
				assert app.review_ready && app.review_snapshot.operation == operation
				check_package_navigation_paste_guard(mut app)
				app.handle('software.row.1')!; assert app.review_selected == 1 && app.selected == 0
				package_plan_cycle(mut app, false)!
				compact := app.build(ui2.rect(0, 0, 320, 240))!
				assert compact.children.any(it.id == 'software.cancel') && !compact.children.any(it.id == 'software.confirm')
				free_window_tree(compact)
				app.handle('software.details')!; assert app.details_mode
				details := app.build(ui2.rect(0, 0, 320, 240))!
				assert details.children.any(it.id == 'software.details.back') && !details.children.any(it.id == 'software.cancel')
				free_window_tree(details)
				app.key_input('\x1b'); assert !app.details_mode && app.review_ready && app.review_selected == 1
				full := app.build(ui2.rect(0, 0, 640, 610))!
				assert full.children.any(it.id == 'software.confirm'); free_window_tree(full)
				app.key_input('\x1b'); assert !app.review_ready && app.review == '' && app.selected == 0
			}
		}
		for mode in ['apply-complete', 'apply-failed']! {
			seed_package_navigation_catalog(mut app)
			app.handle('software.' + operation)!; wait_for_software(mut app)
			assert app.review_ready
			// Confirmation owns the service's reviewed intent, not current selection.
			app.selected = -1
			os.setenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION', mode, true)
			app.handle('software.confirm')!
			wait_for_package_navigation_output(mut app, true); check_package_navigation_writer(mut app)!
			release := u8(`!`); assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
			wait_for_software(mut app)
			assert !app.review_ready && app.review == '' && app.prepare_close()
			if mode == 'apply-failed' {
				assert app.status.contains('disk space changed') && !os.exists(receipt)
				compact := app.build(ui2.rect(0, 0, 320, 240))!
				assert compact.children.any(it.id == 'software.failure') && compact.children.any(it.id == 'software.reload')
				free_window_tree(compact)
				app.handle('software.failure')!; assert app.failure_mode
				app.handle('software.failure.back')!; assert !app.failure_mode
			} else {
				assert json2.decode[[]string](os.read_file(receipt)!)! == ['c'.repeat(64), operation, ...if operation in ['install', 'remove']! { ['editor'] } else { []string{} }]
				assert app.rows.len == 0, 'successful transaction did not reload the catalog'
				os.rm(receipt)!
			}
			os.unsetenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION'); app.clear_failure()
		}
		seed_package_navigation_catalog(mut app)
	}
	// A catalog refresh is a writer, not a read-only package proposal.
	os.setenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION', 'refresh', true)
	app.handle('software.search')!; assert app.focus
	app.handle('software.refresh')!; wait_for_package_navigation_output(mut app, true)
	check_package_navigation_writer(mut app)!
	release := u8(`!`); assert C.write(app.worker.stdio_fd[0], &release, 1) == 1
	wait_for_software(mut app); os.unsetenv('VINIX_SOFTWARE_PACKAGE_NAVIGATION')
	seed_package_navigation_catalog(mut app)
	app.handle('software.details')!; assert app.details_mode
	details := app.build(ui2.rect(0, 0, 320, 240))!
	assert details.children.any(it.id == 'software.details.back'); free_window_tree(details)
	app.handle('software.details.back')!; assert !app.details_mode && app.selected == 0
	compact := app.build(ui2.rect(0, 0, 320, 240))!
	assert compact.children.any(it.id == 'software.reload') && compact.children.any(it.text == app.status)
	free_window_tree(compact)
	app.handle('software.reload')!; wait_for_software(mut app)
	for other in [SoftwareApp{ policy_mode: true }, SoftwareApp{ data_mode: true }, SoftwareApp{ launch_mode: true },
		SoftwareApp{ deployment_mode: true }, SoftwareApp{ mirror_mode: true }, SoftwareApp{ repository_mode: true },
		SoftwareApp{ health_mode: true }, SoftwareApp{ cleanup_mode: true }, SoftwareApp{ audit_mode: true }, SoftwareApp{ snapshot_mode: true }, SoftwareApp{ window_mode: true }]! {
		assert !other.package_screen_active() && !other.package_review_running()
	}
	assert app.query.bytestr() == 'Editor' && app.filter == 1
	println('Software package navigation: all five operations, partial and complete-before-exit Stop/Cancel/Escape, fresh retry, frozen catalog state, compact review/details/status/progress/failures, protected apply/refresh and reload passed')
}

fn check_software_package_navigation_memory() ! {
	$if !track_heap ? { return error('compile with -d track_heap') }
	$if track_heap ? {
		mut texts := []string{cap: 5}
		for operation in package_navigation_operations {
			mut review := package_navigation_review(operation, if operation in ['install', 'remove']! { ['editor'.clone()] } else { []string{} })
			texts << json2.encode(review); review.close()
		}
		arguments := ['apply']
		defer { unsafe { for text in texts { text.free() }; (&array(&texts)).free(); (&array(&arguments)).free() } }
		mut app := SoftwareApp{ output: []u8{cap: 8192}, query: 'Editor'.bytes(), filter: 1 }
		seed_package_navigation_catalog(mut app)
		defer { app.close_app() }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
				for index, text in texts {
					operation := package_navigation_operations[index]
					app.review = operation.clone()
					if operation in ['install', 'remove']! { app.review_names << 'editor'.clone() }
					app.output.clear(); for byte in text { app.output << byte }; app.load_review(); assert app.review_ready
					package_plan_cycle(mut app, false)!
					free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
					app.open_details(); assert app.details_mode
					free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!); app.key_input('\x1b')
					app.key_input('\x1b'); assert !app.review_ready
				}
				app.open_details(); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!); app.handle_details('software.details.back')
				app.capture_failure(arguments, 23); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!); app.clear_failure()
			}
		}
		app.set_status('')
		kept := C.vinix_heap_end(); assert kept == 0, 'package navigation retained ${kept} bytes'
		println('Software package navigation: 1000 catalog and five-operation full/compact/review/details/failure/cancel/retirement cycles retain zero tracked bytes')
		println('Software package plan reader: 1000 five-operation/decode/read/item/page/render/resize/ignored-confirm/Back/cancel/cache-retirement cycles retain zero tracked bytes')
	}
}
