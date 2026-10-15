// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

fn (mut a SoftwareApp) clear_health_report() {
	a.clear_details()
	a.health_snapshot.close()
	unsafe { a.health_matching.free(); a.health_summary.free(); a.health_results.free(); a.health_errors.free() }
	a.health_matching = []int{}
	a.health_summary = ''
	a.health_results = ''
	a.health_errors = []u8{}
	a.health_progress_packages = 0
	a.health_ready = false
	a.health_selected = -1; a.health_scroll = 0
}

fn (mut a SoftwareApp) clear_health() {
	a.clear_health_report()
	a.clear_progress()
	unsafe { a.health_query.free() }
	a.health_query = []u8{}
	a.health_mode = false; a.health_issues_only = false
	a.health_focus = false; a.health_select_all = false
}

fn (mut a SoftwareApp) read_health() {
	// Reload replaces the observation, preserving the report's search and filter.
	a.clear_health_report()
	a.health_mode = true
	a.focus = false; a.select_all = false
	a.health_focus = false; a.health_select_all = false
	mut arguments := ['--json', '--progress', 'health']
	a.start(arguments, true)
	unsafe { (&array(&arguments)).free() }
	if a.worker != unsafe { nil } {
		a.set_status('Inspecting every installed package, runtime and data dependency…')
	}
}

fn (mut a SoftwareApp) health_error(text string) {
	a.worker_failed = true
	unsafe { a.health_errors.flags |= .noslices }
	start := if text.len >= 8192 { text.len - 8191 } else { 0 }
	if start > 0 || a.health_errors.len + text.len - start + 1 > 8192 {
		a.health_errors.clear(); a.output_truncated = true
	}
	for index in start .. text.len { a.health_errors << text[index] }
	a.health_errors << `\n`
}

fn (mut a SoftwareApp) health_progress_line(line string) {
	if !line.starts_with(pkgprotocol.progress_prefix) { a.health_error(line); return }
	if a.worker_failed { return }
	mut event := pkgprotocol.decode_progress(unsafe { tos(line.str + pkgprotocol.progress_prefix.len, line.len - pkgprotocol.progress_prefix.len) }) or {
		unsafe { err.free() }
		a.health_error('Health inspection returned an invalid progress frame. Reload the report.')
		return
	}
	valid := event.path == '' && ((!a.progress_seen && event.phase == 'verify' && event.package == '' && event.repository == '')
		|| (a.progress_seen && a.progress_snapshot.phase == 'verify' &&
			((event.phase == 'verify' && event.package != '' && event.repository != '' && a.health_progress_packages < 4096)
			|| (event.phase == 'complete' && event.package == '' && event.repository == ''))))
	if !valid {
		event.close()
		a.health_error('Health inspection returned out-of-order progress. Reload the report.')
		return
	}
	if event.package != '' { a.health_progress_packages++ }
	a.progress_snapshot.close(); a.progress_snapshot = event; a.progress_seen = true
	if event.phase == 'verify' {
		text := if event.package == '' { 'Inspecting installed software…'.clone() } else { 'Inspecting ' + event.package + '…' }
		a.set_status(text); unsafe { text.free() }
	}
}

fn (mut a SoftwareApp) health_progress_output(text string) {
	unsafe { a.progress_pending.flags |= .noslices }
	for byte in text {
		if byte == `\n` {
			if !a.progress_skip && a.progress_pending.len > 0 { a.health_progress_line(editor_bytes_text(a.progress_pending)) }
			a.progress_pending.clear(); a.progress_skip = false
		} else if !a.progress_skip {
			if a.progress_pending.len >= pkgprotocol.progress_limit {
				a.progress_pending.clear(); a.progress_skip = true; a.output_truncated = true
				a.health_error('Health inspection stderr exceeded its line limit. Reload the report.')
			} else { a.progress_pending << byte }
		}
	}
}

fn (mut a SoftwareApp) finish_health_output(code int) {
	if a.progress_pending.len > 0 || a.progress_skip {
		a.health_error('Health inspection stderr ended with an incomplete line. Reload the report.')
		if a.progress_pending.len > 0 { a.health_error(editor_bytes_text(a.progress_pending)) }
	}
	a.progress_pending.clear(); a.progress_skip = false
	if code == 0 && !a.worker_failed && (!a.progress_seen || a.progress_snapshot.phase != 'complete') {
		a.health_error('Health inspection ended without complete progress. Reload the report.')
	}
	if code == 0 && !a.worker_failed && !a.load_health() {
		a.health_error(a.status)
	}
	if code != 0 || a.worker_failed {
		if a.health_errors.len == 0 { a.health_error(if a.worker_failed { a.status } else { 'Health inspection failed before a complete report was available.' }) }
		a.output.clear()
		for byte in a.health_errors { a.output << byte }
	}
}

fn (mut a SoftwareApp) stop_health() {
	if !a.health_mode || !a.worker_health || a.worker == unsafe { nil } { return }
	if a.worker.is_alive() { a.worker.signal_kill(); a.worker.wait() }
	a.retire_worker()
	a.clear_health_report(); a.clear_progress(); a.output.clear()
	a.worker_health = false
	a.set_status('Inspection stopped. No report was accepted. Reload to inspect installed software again.')
}

fn software_health_issue_label(issue string) string {
	return match issue {
		'namespace' { 'Namespace' }
		'payload' { 'Payload' }
		'registration' { 'Launcher' }
		else { 'Verified' }
	}
}

fn software_health_matches(row pkgprotocol.PackageHealth, query string) bool {
	if query == '' { return true }
	for value in [row.id, row.name, row.version, row.kind, row.repository, row.public_key,
		row.issue, software_health_issue_label(row.issue), row.diagnostic]! {
		text := software_search_lower(value)
		found := text.contains(query)
		unsafe { text.free() }
		if found { return true }
	}
	return false
}

fn (mut a SoftwareApp) filter_health() {
	a.health_matching.clear()
	unsafe { a.health_matching.flags |= .noslices }
	query := software_search_lower(if a.health_query.len == 0 { '' } else { editor_bytes_text(a.health_query) })
	defer { unsafe { query.free() } }
	// Keep canonical row identity and issue-first ordering under both filters.
	for issues in [true, false]! {
		if !issues && a.health_issues_only { continue }
		for index, row in a.health_snapshot.rows {
			if (row.issue != '') == issues && software_health_matches(row, query) { a.health_matching << index }
		}
	}
	previous := a.health_selected
	if a.health_selected !in a.health_matching {
		a.health_selected = if a.health_matching.len == 0 { -1 } else { a.health_matching[0] }
	}
	a.health_scroll = 0
	for position, index in a.health_matching {
		if index == a.health_selected {
			size := if a.page_rows > 0 { a.page_rows } else { 1 }
			a.health_scroll = position / size * size
			break
		}
	}
	if previous != a.health_selected { a.prepare_health_details() }
	visible := a.health_matching.len.str()
	total := a.health_snapshot.rows.len.str()
	unsafe { a.health_results.free() }
	a.health_results = 'Showing ' + visible + ' of ' + total
	unsafe { visible.free(); total.free() }
}

fn (mut a SoftwareApp) health_paste_input(input string) {
	if a.worker != unsafe { nil } || !a.health_ready || !a.health_focus { return }
	unsafe { a.health_query.flags |= .noslices }
	console_paste_field(mut a.health_query, input, console_filter_limit, a.health_select_all)
	a.health_select_all = false
	a.filter_health()
}

fn (mut a SoftwareApp) health_key_input(input string) {
	if a.worker != unsafe { nil } { if input == '\x1b' { a.stop_health() }; return }
	if input == '\x1b' {
		if a.health_focus { a.health_focus = false; a.health_select_all = false } else { a.clear_health() }
		return
	}
	if !a.health_ready || !a.health_focus { return }
	match input {
		'\x01' { a.health_select_all = true }
		'\x7f', '\x08' {
			console_backspace(mut a.health_query, a.health_select_all)
			a.health_select_all = false
			a.filter_health()
		}
		'\r', '\n' { a.health_focus = false; a.health_select_all = false }
		else { a.health_paste_input(input) }
	}
}

fn (mut a SoftwareApp) prepare_health_details() {
	a.clear_details()
	if !a.health_ready || a.health_selected < 0 || a.health_selected >= a.health_snapshot.rows.len { return }
	row := a.health_snapshot.rows[a.health_selected]
	a.details_pages = []SoftwareDetailsPage{cap: 8}
	unsafe { a.details_pages.flags |= .noslices }
	mut values := ['Package ID: ' + row.id, 'Name: ' + row.name, 'Installed version: ' + row.version,
		'Architecture: ' + a.health_snapshot.architecture,
		'Kind: ' + row.kind, 'Installed repository: ' + row.repository, 'Installed publisher key: ' + row.public_key,
		'Integrity: ' + if row.issue == '' { 'Verified installed files and registration' } else { row.issue },
		if row.diagnostic == '' { 'No issue found in this package’s own tree.'.clone() } else { 'Diagnostic: ' + row.diagnostic }]
	a.details_values(0, values)
	software_policy_free_lines(mut values)
	total := a.details_pages.len.str()
	for index in 0 .. a.details_pages.len {
		number := (index + 1).str()
		a.details_pages[index].label = number + ' of ' + total
		unsafe { number.free() }
	}
	unsafe { total.free() }
}

fn (mut a SoftwareApp) load_health() bool {
	mut report := pkgprotocol.decode_health(editor_bytes_text(a.output)) or {
		unsafe { err.free() }
		a.set_status('Invalid or incomplete health report. Reload before reviewing repairs.')
		return false
	}
	if a.worker_health && report.rows.len != a.health_progress_packages {
		report.close()
		a.set_status('Health report package count does not match the completed scan. Reload the report.')
		return false
	}
	a.clear_details()
	a.health_snapshot.close()
	a.health_snapshot = report
	a.health_ready = true
	a.health_selected = -1
	a.filter_health()
	count := report.rows.len.str()
	issues := report.rows.filter(it.issue != '')
	damaged := issues.len.str()
	number := report.generation.str()
	unsafe { a.health_summary.free() }
	a.health_summary = 'Generation ${number} · ${count} packages inspected · ${damaged} with issues'
	unsafe { count.free(); damaged.free(); number.free(); (&array(&issues)).free() }
	a.set_status('Integrity observation only: each row describes its own tree and first issue. Trust, policy and dependencies still gate launch. Repair review covers all installed packages and retains personal data.')
	return true
}

fn (mut a SoftwareApp) handle_health(event_id string) {
	match event_id {
		'software.health.back' { a.clear_health() }
		'software.health.reload' { a.read_health() }
		'software.health.search' { if a.health_ready { a.health_focus = true } }
		'software.health.issues' {
			if !a.health_ready { return }
			a.health_issues_only = !a.health_issues_only
			a.health_focus = false; a.health_select_all = false
			a.filter_health()
		}
		'software.health.repair' {
			if !a.health_ready || a.health_snapshot.rows.len == 0 { return }
			a.clear_health()
			a.begin_review('repair', [])
		}
		'software.health.up' { a.health_scroll = if a.health_scroll > a.page_rows { a.health_scroll - a.page_rows } else { 0 } }
		'software.health.down' { if a.health_scroll + a.page_rows < a.health_matching.len { a.health_scroll += a.page_rows } }
		'software.health.previous' { if a.details_page > 0 { a.details_page-- } }
		'software.health.next' { if a.details_page + 1 < a.details_pages.len { a.details_page++ } }
		else {
			if !a.health_ready { return }
			for slot, action in software_row_actions {
				if event_id == action && a.health_scroll + slot < a.health_matching.len {
					a.health_selected = a.health_matching[a.health_scroll + slot]
					a.health_focus = false; a.health_select_all = false
					a.prepare_health_details()
					return
				}
			}
		}
	}
}

fn (mut a SoftwareApp) build_health_compact(width int, height int) ui2.Element {
	mut children := frame_elements(3)
	content_width := if width > 28 { width - 28 } else { 1 }
	if a.worker == unsafe { nil } {
		children << software_button('software.health.back', 'Back to packages', 14, 8, if content_width >= 160 { 160 } else { content_width })
	} else {
		children << software_button('software.health.stop', 'Stop inspection', 14, 8, if content_width >= 160 { 160 } else { content_width })
	}
	children << software_label('Installed software health', 14, 46, content_width, 28, false)
	children << software_label('Enlarge this window to search the report and view package diagnostics.', 14, 80, content_width, if height > 140 { 60 } else { 28 }, false)
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) build_health(width int, height int) ui2.Element {
	mut children := frame_elements(40)
	children << software_label('Installed software health', 14, 8, width - 202, 28, false)
	children << software_button(if a.worker == unsafe { nil } { 'software.health.back' } else { 'software.health.stop' },
		if a.worker == unsafe { nil } { 'Back to packages' } else { 'Stop inspection' }, width - 174, 8, 160)
	children << software_label(a.health_summary, 14, 46, width - 28, 36, false)
	if a.health_ready {
		children << software_label('Search', 14, 90, 56, 28, false)
		children << console_field('software.health.search', if a.health_query.len == 0 { '' } else { editor_bytes_text(a.health_query) }, 76, 90, width - 224, a.health_focus)
		children << ui2.button('software.health.issues', 'Issues only', ui2.rect(f64(width - 138), 90, 124, 28),
			ui2.BoxStyle{ bg: if a.health_issues_only { settings_choice_bg } else { body_panel }, radius: 3 },
			ui2.TextStyle{ color: body_text, size: 12, align: .center })
		children << software_label(a.health_results, 14, height - 214, 236, 28, false)
		if a.health_matching.len == 0 {
			children << software_label(if a.health_snapshot.rows.len == 0 { 'No packages are installed.' } else { 'No packages match this search and filter.' }, 14, 128, 236, 72, false)
		}
		for slot in 0 .. a.page_rows {
			index := a.health_scroll + slot
			if index >= a.health_matching.len { break }
			row_index := a.health_matching[index]
			row := a.health_snapshot.rows[row_index]
			children << ui2.Element{
				...ui2.button(software_row_actions[slot], software_health_issue_label(row.issue) + ': ' + row.id, ui2.rect(14, f64(128 + slot * 30), 236, 28),
				ui2.BoxStyle{ bg: if row_index == a.health_selected { settings_choice_bg } else { body_panel }, radius: 3 },
				ui2.TextStyle{ color: body_text, size: 12, align: .left })
				key: workflow_owned_text_key
			}
		}
		if a.details_page >= 0 && a.details_page < a.details_pages.len {
			page := a.details_pages[a.details_page]
			children << ui2.label('', page.text, ui2.rect(274, 128, f64(width - 288), f64(height - 342)),
				ui2.TextStyle{ color: body_text, size: 12, lines: 14 })
			children << software_label(page.label, 274, height - 214, width - 288, 28, false)
			children << software_button('software.health.previous', 'Previous detail', 274, height - 176, 142)
			children << software_button('software.health.next', 'Next detail', 428, height - 176, 142)
		}
		children << software_button('software.health.up', 'Previous packages', 14, height - 176, 110)
		children << software_button('software.health.down', 'Next packages', 136, height - 176, 110)
		if a.health_snapshot.rows.len > 0 { children << software_button('software.health.repair', 'Review all repairs', 396, height - 138, 160) }
	}
	if a.worker == unsafe { nil } { children << software_button('software.health.reload', 'Reload report', 274, height - 138, 110) }
	progress := a.worker != unsafe { nil } && a.progress_seen
	if progress { children << a.progress_bar(width, height) }
	a.add_status_footer(mut children, width, height, progress)
	return ui2.screen(app_surface, children)
}
