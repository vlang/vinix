// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import desktop.packagecore

fn report_fixture_selected(a &SoftwareApp) int {
	return if a.data_mode { a.data_selected } else if a.health_mode { a.health_selected } else { a.audit_selected }
}

fn report_fixture_indices(a &SoftwareApp) []int {
	return if a.data_mode { []int{len: a.data_status.rows.len, init: index} }
		else if a.health_mode { a.health_matching.clone() } else { a.audit_matching.clone() }
}

fn check_report_return_selection(mut app SoftwareApp) ! {
	selected := report_fixture_selected(&app); page := app.details_page; short_page := app.details_compact_page
	health_scroll := app.health_scroll; audit_scroll := app.audit_scroll; page_rows := app.page_rows
	data_scroll := app.data_scroll
	free_window_tree(app.build(ui2.rect(0, 0, 900, 900))!)
	assert app.page_rows == 16
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	app.handle('software.report.read')!
	indices := report_fixture_indices(&app)
	defer { unsafe { (&array(&indices)).free() } }
	for report_fixture_selected(&app) != indices[indices.len - 1] { app.key_input('\x1b[B') }
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	assert app.page_rows == 16
	app.key_input('\x1b')
	tree := app.build(ui2.rect(0, 0, 640, 610))!
	position := indices.index(report_fixture_selected(&app))
	list_scroll := if app.data_mode { app.data_scroll } else if app.health_mode { app.health_scroll } else { app.audit_scroll }
	assert position >= list_scroll && position < list_scroll + app.page_rows,
		'selected package hidden after returning to a smaller report'
	assert tree.children.any(it.id.starts_with('software.row.') && it.box.bg == settings_choice_bg)
	free_window_tree(tree)
	app.handle(if app.data_mode { 'software.data.up' } else if app.health_mode { 'software.health.up' } else { 'software.audit.up' })!
	away := if app.data_mode { app.data_scroll } else if app.health_mode { app.health_scroll } else { app.audit_scroll }
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	assert (if app.data_mode { app.data_scroll } else if app.health_mode { app.health_scroll } else { app.audit_scroll }) == away
	app.health_scroll = health_scroll; app.audit_scroll = audit_scroll; app.page_rows = page_rows
	app.data_scroll = data_scroll
	if app.data_mode { app.data_selected = selected; app.prepare_personal_data_details() }
	else if app.health_mode { app.health_selected = selected; app.prepare_health_details() }
	else { app.audit_selected = selected; app.prepare_deployment_audit_details() }
	app.details_page = page; app.details_compact_page = short_page
}

fn check_software_report_reader(mut app SoftwareApp) ! {
	page := app.details_page; short_page := app.details_compact_page
	health_selected := app.health_selected; audit_selected := app.audit_selected
	health_scroll := app.health_scroll; audit_scroll := app.audit_scroll
	data_selected := app.data_selected; data_scroll := app.data_scroll; data_pending := app.data_pending
	data_ready := app.data_ready; data_rows := app.data_status.rows.data; data_result := app.data_result
	query := editor_bytes_text(app.query); health_query := editor_bytes_text(app.health_query); audit_query := editor_bytes_text(app.audit_query)
	selected := app.selected; filter := app.filter; scroll := app.scroll; page_rows := app.page_rows
	issues := app.health_issues_only; differences := app.audit_differences_only
	path := app.audit_path; saved := app.snapshot_pending; digest := app.snapshot_saved.sha256
	audit_digest := app.audit_snapshot.deployment_sha256; status := app.status
	cleanup_fingerprint := app.cleanup_snapshot.fingerprint; cleanup_scroll := app.cleanup_scroll
	cleanup_summary := app.cleanup_summary; cleanup_result := app.cleanup_result
	cleanup_generations := app.cleanup_snapshot.generations.data; cleanup_ready := app.cleanup_ready
	repository_ready := app.repository_review_ready; repository_operation := app.repository_operation
	repository_fingerprint := app.repository_review.fingerprint; repository_source := app.repository_review.url
	repository_key := app.repository_review.public_key; repository_pending := app.repository_pending
	repository_page := app.repository_url_page; repository_seen := app.repository_url_seen
	repository_selected := app.repository_selected; repository_scroll := app.repository_scroll
	repository_id := editor_bytes_text(app.repository_id); repository_url := editor_bytes_text(app.repository_url)
	repository_key_field := editor_bytes_text(app.repository_key)
	storage := app.details_compact_pages.data
	assert app.details_compact_pages.len > app.details_pages.len
	for canonical, full in app.details_pages {
		mut bytes := []u8{cap: full.text.len}
		for short in app.details_compact_pages {
			if short.source_page != canonical { continue }
			for byte in short.text { if byte != `\n` { bytes << byte } }
		}
		expected := full.text.replace('\n', '')
		assert editor_bytes_text(bytes) == expected
		unsafe { bytes.free(); expected.free() }
	}
	home := app.build(ui2.rect(0, 0, 320, 240))!
	assert home.children.any(it.id == 'software.report.read'); free_window_tree(home)
	app.handle('software.report.read')!; assert app.report_reader_mode
	for app.details_page > 0 { app.handle('software.report.previous')! }
	// Entering from a later canonical page anchors its first compact fragment.
	app.details_compact_page = 0
	for index, short in app.details_compact_pages {
		for size in [ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 320, 240)]! {
			tree := app.build(size)!
			assert app.details_compact_mode && app.details_compact_page == index && app.details_page == short.source_page
			details_fixture_rendered_lines(&tree, short.text, 14, 118, int(size.width) - 28, 18, 12)
			for id in ['software.report.back', 'software.report.previous', 'software.report.next']! { assert tree.children.any(it.id == id) }
			assert tree.children.any(it.text == short.label)
			assert tree.children.any(it.id == 'software.report.package.next') == app.report_has_packages()
			assert !tree.children.any(it.id in ['software.health.repair', 'software.audit.review', 'software.snapshot.export', 'software.snapshot.review',
				'software.cleanup.confirm', 'software.cleanup.reload', 'software.failure'])
			assert !tree.children.any(it.id in ['software.repository.confirm', 'software.repository.cancel', 'software.repository.url-next'])
			assert !tree.children.any(it.id in ['software.data.confirm', 'software.data.delete', 'software.data.cancel', 'software.data.reload'])
			for element in tree.children {
				assert element.frame.x >= 0 && element.frame.x + element.frame.width <= size.width
				assert element.frame.y >= 0 && element.frame.y + element.frame.height <= size.height
			}
			free_window_tree(tree)
		}
		if index % 3 == 0 { app.key_input('\x1b[C') }
		else if index % 3 == 1 { app.key_input('\x1b[6~') }
		else { app.handle('software.report.next')! }
		assert app.details_compact_page == if index + 1 < app.details_compact_pages.len { index + 1 } else { index }
	}
	last := app.details_compact_page
	app.key_input('\x1b[5~'); assert app.details_compact_page == last - 1
	for app.details_compact_page > 0 { app.key_input('\x1b[D') }
	app.key_input('\x1b[D'); assert app.details_compact_page == 0
	app.key_input('\x1b[C'); app.key_input('\x1b[C')
	anchor := app.details_compact_page; canonical := app.details_page
	for size in [ui2.rect(0, 0, 900, 660), ui2.rect(0, 0, 180, 220), ui2.rect(0, 0, 180, 96),
		ui2.rect(0, 0, 160, 240), ui2.rect(0, 0, 320, 240)]! {
		tree := app.build(size)!
		assert app.details_compact_page == anchor && app.details_page == canonical
		assert tree.children.any(it.id == 'software.report.back')
		if size.width < 180 || size.height < 220 {
			assert !tree.children.any(it.id == 'software.report.next') && !tree.children.any(it.text_style.font_family == 'mono')
		} else if size.width >= 640 && size.height >= 610 {
			details_fixture_rendered_lines(&tree, app.details_pages[canonical].text, 14, 94, int(size.width) - 28, 20, 52)
		}
		for element in tree.children {
			assert element.frame.x >= 0 && element.frame.x + element.frame.width <= size.width
			assert element.frame.y >= 0 && element.frame.y + element.frame.height <= size.height
		}
		free_window_tree(tree)
	}
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	app.key_input('\x1b[6~'); free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	assert app.details_compact_pages[app.details_compact_page].source_page == app.details_page
	if app.details_page != canonical {
		assert app.details_compact_page == 0 || app.details_compact_pages[app.details_compact_page - 1].source_page != app.details_page
	}
	for action in ['software.health.reload', 'software.health.repair', 'software.health.issues', 'software.health.search',
		'software.cleanup.confirm', 'software.cleanup.reload', 'software.cleanup.back', 'software.cleanup.stop', 'software.cleanup.cancel',
		'software.cleanup.up', 'software.cleanup.down',
		'software.repository.confirm', 'software.repository.cancel', 'software.repository.back', 'software.repository.stop',
		'software.repository.reload', 'software.repository.new', 'software.repository.enroll', 'software.repository.revoke',
		'software.repository.url-next', 'software.repository.url-previous', 'software.repository.id', 'software.repository.url', 'software.repository.key',
		'software.data.confirm', 'software.data.delete', 'software.data.cancel', 'software.data.reload', 'software.data.back',
		'software.data.stop', 'software.data.up', 'software.data.down',
		'software.audit.reload', 'software.audit.review', 'software.audit.differences', 'software.audit.search',
		'software.snapshot.another', 'software.snapshot.save', 'software.snapshot.audit', 'software.snapshot.review', 'software.snapshot.export',
		'software.deployment.path', 'software.cancel', 'software.confirm', 'software.failure', 'software.row.0',
		packagecore.request_prefix + '{"id":"editor"}'] { app.handle(action)! }
	app.key_input('typed'); app.key_input('\r'); app.key_input('\x01')
	app.paste_input('changed'); app.paste_input('\x1b'); app.paste_input('\x1b[C')
	assert app.report_reader_mode && app.worker == unsafe { nil } && !app.admin_prompt && app.review == ''
	assert editor_bytes_text(app.query) == query && editor_bytes_text(app.health_query) == health_query && editor_bytes_text(app.audit_query) == audit_query
	assert app.selected == selected && app.filter == filter && app.scroll == scroll && app.page_rows == page_rows
	assert app.health_issues_only == issues && app.audit_differences_only == differences
	assert app.audit_path == path && app.snapshot_pending == saved && app.snapshot_saved.sha256 == digest && app.audit_snapshot.deployment_sha256 == audit_digest
	assert app.status == status && app.details_compact_pages.data == storage
	assert app.cleanup_snapshot.fingerprint == cleanup_fingerprint && app.cleanup_scroll == cleanup_scroll && app.cleanup_ready == cleanup_ready
	assert app.cleanup_snapshot.generations.data == cleanup_generations && app.cleanup_summary == cleanup_summary && app.cleanup_result == cleanup_result
	assert app.repository_review_ready == repository_ready && app.repository_operation == repository_operation
	assert app.repository_review.fingerprint == repository_fingerprint && app.repository_review.url == repository_source && app.repository_review.public_key == repository_key
	assert app.repository_pending == repository_pending && app.repository_url_page == repository_page && app.repository_url_seen == repository_seen
	assert app.repository_selected == repository_selected && app.repository_scroll == repository_scroll
	assert editor_bytes_text(app.repository_id) == repository_id && editor_bytes_text(app.repository_url) == repository_url && editor_bytes_text(app.repository_key) == repository_key_field
	assert app.data_selected == data_selected && app.data_scroll == data_scroll && app.data_pending == data_pending
	assert app.data_ready == data_ready && app.data_status.rows.data == data_rows && app.data_result == data_result
	if app.report_has_packages() {
		indices := report_fixture_indices(&app)
		defer { unsafe { (&array(&indices)).free() } }
		for report_fixture_selected(&app) != indices[0] { app.key_input(if report_fixture_selected(&app) < indices[0] { '\x1b[B' } else { '\x1b[A' }) }
		app.handle('software.report.package.previous')!; assert report_fixture_selected(&app) == indices[0]
		for position, row in indices {
			assert report_fixture_selected(&app) == row && app.report_reader_mode
			free_window_tree(app.build(ui2.rect(0, 0, 180, 220))!)
			if position % 3 == 0 { app.key_input('\x1b[B') }
			else if position % 3 == 1 { app.key_input('\t') }
			else { app.handle('software.report.package.next')! }
			assert report_fixture_selected(&app) == if position + 1 < indices.len { indices[position + 1] } else { row }
		}
		if indices.len > 1 {
			app.key_input('\x1b[Z'); assert report_fixture_selected(&app) == indices[indices.len - 2]
		}
		assert app.health_issues_only == issues && app.audit_differences_only == differences
		app.key_input('\x1b'); assert !app.report_reader_mode
		app.health_selected = health_selected; app.audit_selected = audit_selected
		if app.data_mode { app.data_selected = data_selected; app.prepare_personal_data_details() }
		else if app.health_mode { app.prepare_health_details() } else { app.prepare_deployment_audit_details() }
	} else {
		before := app.details_page
		app.key_input('\t'); app.key_input('\x1b[A'); app.key_input('\x1b[Z')
		assert app.details_page == before
		app.key_input('\x1b'); assert !app.report_reader_mode
	}
	app.health_scroll = health_scroll; app.audit_scroll = audit_scroll
	app.data_scroll = data_scroll
	app.details_page = page; app.details_compact_page = short_page
	app.handle('software.report.read')!; app.handle('software.report.back')!
	assert !app.report_reader_mode && app.audit_path == path && app.snapshot_pending == saved && app.status == status
	println('Software report reader: complete health/audit/receipt UTF-8 pages, native lines, keyboard and filtered package traversal, resize/tiny Back, read-only modal isolation and retained source/digests passed')
}

fn report_reader_cycle(mut app SoftwareApp) ! {
	page := app.details_page; selected := report_fixture_selected(&app)
	health_scroll := app.health_scroll; audit_scroll := app.audit_scroll
	data_scroll := app.data_scroll; data_pending := app.data_pending
	app.handle('software.report.read')!; assert app.report_reader_mode
	free_window_tree(app.build(ui2.rect(0, 0, 180, 220))!)
	app.key_input('\x1b[C'); app.key_input('\t')
	free_window_tree(app.build(ui2.rect(0, 0, 640, 610))!)
	free_window_tree(app.build(ui2.rect(0, 0, 320, 240))!)
	app.handle('software.snapshot.export')!; app.handle('software.audit.review')!; app.handle('software.health.repair')!
	app.handle('software.cleanup.confirm')!; app.handle('software.cleanup.reload')!; app.handle('software.cleanup.back')!
	app.handle('software.repository.confirm')!; app.handle('software.repository.cancel')!; app.handle('software.repository.url-next')!
	app.handle('software.data.confirm')!; app.handle('software.data.delete')!; app.handle('software.data.cancel')!; app.handle('software.data.reload')!
	assert app.worker == unsafe { nil } && !app.admin_prompt && app.report_reader_mode
	assert app.data_pending == data_pending
	app.key_input('\x1b'); assert !app.report_reader_mode
	if app.report_has_packages() && report_fixture_selected(&app) != selected {
		if app.data_mode { app.data_selected = selected; app.prepare_personal_data_details() }
		else if app.health_mode { app.health_selected = selected; app.prepare_health_details() }
		else { app.audit_selected = selected; app.prepare_deployment_audit_details() }
	}
	app.health_scroll = health_scroll; app.audit_scroll = audit_scroll; app.details_page = page
	app.data_scroll = data_scroll
}
