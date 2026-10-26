// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

fn (mut a SoftwareApp) clear_deployment_audit_report() {
	a.clear_details()
	a.audit_snapshot.close()
	unsafe { a.audit_summary.free(); a.audit_results.free(); a.audit_matching.free() }
	a.audit_summary = ''; a.audit_results = ''; a.audit_matching = []int{}
	a.audit_ready = false; a.audit_selected = -1; a.audit_scroll = 0
	a.audit_focus = false; a.audit_select_all = false
}

fn (mut a SoftwareApp) clear_deployment_audit() {
	a.clear_deployment_audit_report()
	unsafe { a.audit_path.free(); a.audit_query.free() }
	a.audit_query = []u8{}; a.audit_differences_only = false
	a.audit_path = ''; a.audit_mode = false
}

fn (mut a SoftwareApp) read_deployment_audit() {
	a.clear_deployment_audit_report()
	a.focus = false; a.select_all = false
	mut args := ['--json', 'deployment-audit', a.audit_path]
	a.start(args, true)
	unsafe { (&array(&args)).free() }
	if a.worker != unsafe { nil } {
		a.worker_audit = true
		a.set_status('Comparing the deployment lock with installed metadata…')
	}
}

fn (mut a SoftwareApp) begin_deployment_audit() {
	path := editor_bytes_text(a.deployment_path)
	if !software_deployment_path_valid(path) {
		a.set_status('Enter an absolute deployment file path without control characters (at most 4096 bytes).')
		return
	}
	a.clear_review()
	a.clear_deployment_audit()
	a.audit_path = path.clone()
	a.audit_mode = true
	a.read_deployment_audit()
}

fn (mut a SoftwareApp) prepare_deployment_audit_details() {
	a.clear_details()
	if !a.audit_ready { return }
	a.details_pages = []SoftwareDetailsPage{cap: 16}
	unsafe { a.details_pages.flags |= .noslices }
	mut values := ['Deployment file: ' + a.audit_path, 'Captured lock SHA-256: ' + a.audit_snapshot.deployment_sha256,
		'Architecture: ' + a.audit_snapshot.architecture]
	unsafe { values.flags |= .noslices }
	software_details_count(mut values, 'Installed generation: ', a.audit_snapshot.generation)
	if a.audit_selected >= 0 && a.audit_selected < a.audit_snapshot.rows.len {
		row := a.audit_snapshot.rows[a.audit_selected]
		values << 'Package: ' + row.id
		values << 'Result: ' + row.status
		values << 'Expected version: ' + if row.expected_version == '' { 'Absent from deployment' } else { row.expected_version }
		values << 'Installed version: ' + if row.installed_version == '' { 'Not installed' } else { row.installed_version }
		for field in row.differences { values << 'Changed field: ' + field }
		if 'sequence' in row.differences { values << 'The installed publisher sequence is below the lock minimum.'.clone() }
		if 'requested' in row.differences { values << 'The explicitly requested application set differs.'.clone() }
	}
	values << 'Recorded metadata only. Health checks payload integrity; trust and policy apply during reviewed changes.'.clone()
	a.details_values_columns(0, values, 24)
	software_policy_free_lines(mut values)
	total := a.details_pages.len.str()
	for index in 0 .. a.details_pages.len {
		number := (index + 1).str()
		a.details_pages[index].label = number + ' of ' + total
		unsafe { number.free() }
	}
	unsafe { total.free() }
	a.prepare_report_reader()
}

fn (mut a SoftwareApp) load_deployment_audit(code int) bool {
	mut report := pkgprotocol.decode_deployment_audit(editor_bytes_text(a.output)) or {
		unsafe { err.free() }
		a.set_status('Invalid or incomplete deployment audit. Check the file and reload the report.')
		return false
	}
	if (code == 0) != report.matches {
		report.close()
		a.set_status('Deployment audit exit status disagrees with its result. Reload the report.')
		return false
	}
	a.audit_snapshot = report
	a.audit_ready = true
	mut differences := 0
	for row in report.rows {
		if row.status != 'match' {
			differences++
		}
	}
	count := report.rows.len.str(); changed := differences.str(); generation := report.generation.str()
	a.audit_summary = 'Generation ' + generation + ' · ' + count + ' packages · ' + changed + ' differences'
	unsafe { count.free(); changed.free(); generation.free() }
	a.filter_deployment_audit()
	a.set_status(if report.matches { 'Installed metadata matches the deployment lock. Health and current trust are separate checks.' }
		else { 'Installed metadata differs. Inspect the rows, then request a fresh deployment review to reconcile the complete application set.' })
	return true
}

fn (mut a SoftwareApp) finish_deployment_audit(code int) {
	if code in [0, 3]! && !a.worker_failed {
		if a.load_deployment_audit(code) { return }
		a.worker_failed = true
		a.output.clear()
		for byte in a.status { a.output << byte }
	} else if a.worker_failed {
		a.output.clear()
		for byte in a.status { a.output << byte }
	} else {
		diagnostic := software_output_tail(a.output)
		a.set_status(if diagnostic.len > 0 { diagnostic } else { 'Deployment check failed before a complete report was available.' })
		unsafe { diagnostic.free() }
	}
	a.capture_failure(a.worker.args, code)
}

fn (mut a SoftwareApp) stop_deployment_audit() {
	if !a.worker_audit || a.worker == unsafe { nil } { return }
	if a.worker.is_alive() { a.worker.signal_kill(); a.worker.wait() }
	a.retire_worker(); a.worker_audit = false
	a.clear_deployment_audit_report(); a.output.clear()
	a.set_status('Deployment check stopped. Reload to compare installed metadata again.')
}

fn (mut a SoftwareApp) handle_deployment_audit(event_id string) {
	if event_id in ['software.audit.back', 'software.audit.stop']! {
		a.stop_deployment_audit()
		if event_id == 'software.audit.back' { a.clear_deployment_audit() }
		return
	}
	if a.worker != unsafe { nil } { return }
	match event_id {
		'software.audit.search' { if a.audit_ready { a.audit_focus = true } }
		'software.audit.differences' {
			if !a.audit_ready { return }
			a.audit_differences_only = !a.audit_differences_only
			a.audit_focus = false; a.audit_select_all = false
			a.filter_deployment_audit()
		}
		'software.audit.reload' { a.read_deployment_audit() }
		'software.audit.review' {
			if !a.audit_ready { return }
			// Capture the report's literal source before retiring it. The service
			// reads it anew and binds a fresh authenticated deployment proposal.
			a.deployment_path.clear()
			for byte in a.audit_path { a.deployment_path << byte }
			a.clear_deployment_audit()
			a.begin_deployment_review()
		}
		'software.audit.previous' { if a.details_page > 0 { a.details_page-- } }
		'software.audit.next' { if a.details_page + 1 < a.details_pages.len { a.details_page++ } }
		'software.audit.up' { if a.audit_scroll >= a.page_rows { a.audit_scroll -= a.page_rows } else { a.audit_scroll = 0 } }
		'software.audit.down' { if a.audit_scroll + a.page_rows < a.audit_matching.len { a.audit_scroll += a.page_rows } }
		else {
			for slot, action in software_row_actions {
				if event_id == action && a.audit_ready && a.audit_scroll + slot < a.audit_matching.len {
					a.audit_selected = a.audit_matching[a.audit_scroll + slot]
					a.audit_focus = false; a.audit_select_all = false
					a.prepare_deployment_audit_details()
					return
				}
			}
		}
	}
}

fn (mut a SoftwareApp) build_deployment_audit_compact(width int, height int) ui2.Element {
	mut children := frame_elements(9)
	idle := a.worker == unsafe { nil }
	failed := idle && a.failure_pages.len > 0
	if width < 320 || height < 240 {
		children << software_label('Deployment check · enlarge for details', 14, 8, width - 28, 28, false)
		button_width := if failed { (width - 42) / 2 } else { if width > 202 { 174 } else { width - 28 } }
		children << software_button(if idle { 'software.audit.back' } else { 'software.audit.stop' },
			if idle { 'Back' } else { 'Stop check' }, 14, 46, button_width)
		if failed { children << software_button('software.failure', 'Failure', (width + 14) / 2, 46, button_width) }
		if height > 112 { children << software_label(a.status, 14, 84, width - 28, height - 92, false) }
		return ui2.screen(app_surface, children)
	}
	children << software_label('Installed deployment check', 14, 8, width - 28, 28, false)
	children << software_button(if a.worker == unsafe { nil } { 'software.audit.back' } else { 'software.audit.stop' },
		if idle { 'Back to deployment' } else { 'Stop check' }, 14, 46, 140)
	if idle { children << software_button('software.audit.reload', 'Reload check', width - 154, 46, 140) }
	children << software_label(a.status, 14, 84, width - 28, 28, false)
	children << software_label(if a.audit_ready { a.audit_results } else if idle { 'Reload to compare installed metadata.' }
		else { 'Wait for the report or stop this check.' }, 14, 118, width - 28, 28, false)
	reading := idle && a.audit_ready && a.details_pages.len > 0
	button_width := if failed && reading { (width - 52) / 3 } else { 140 }
	if a.status_readable() { children << software_button('software.status', 'Read status', 14, 156, button_width) }
	if reading { children << software_button('software.report.read', 'Read report', if failed { 26 + button_width } else { width - 154 }, 156, button_width) }
	if failed { children << software_button('software.failure', if reading { 'Failure' } else { 'Failure details' }, width - 14 - button_width, 156, button_width) }
	children << software_label('Enlarge to search or filter packages.', 14, 194, width - 28, height - 202, false)
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) build_deployment_audit(width int, height int) ui2.Element {
	previous_size := a.page_rows
	a.page_rows = (height - 334) / 30
	if a.page_rows > software_row_actions.len { a.page_rows = software_row_actions.len }
	if a.page_rows != previous_size { a.keep_audit_selection_visible() }
	mut children := frame_elements(56)
	children << software_label('Installed deployment check', 14, 8, width - 202, 28, false)
	children << software_button(if a.worker == unsafe { nil } { 'software.audit.back' } else { 'software.audit.stop' },
		if a.worker == unsafe { nil } { 'Back to deployment' } else { 'Stop check' }, width - 188, 8, 174)
	children << software_label(a.audit_summary, 14, 46, width - 28, 36, false)
	if a.audit_ready {
		children << software_label('Search', 14, 90, 56, 28, false)
		children << console_field('software.audit.search', if a.audit_query.len == 0 { '' } else { editor_bytes_text(a.audit_query) }, 76, 90, width - 252, a.audit_focus)
		children << ui2.button('software.audit.differences', 'Differences only', ui2.rect(f64(width - 164), 90, 150, 28),
			ui2.BoxStyle{ bg: if a.audit_differences_only { settings_choice_bg } else { body_panel }, radius: 3 },
			ui2.TextStyle{ color: body_text, size: 12, align: .center })
		children << software_label(a.audit_results, 14, height - 206, 236, 28, false)
		if a.audit_matching.len == 0 {
			children << software_label(if a.audit_snapshot.rows.len == 0 { 'No package metadata in either set.' }
				else { 'No packages match this search and filter.' }, 14, 128, 236, 72, false)
		}
		for slot in 0 .. a.page_rows {
			index := a.audit_scroll + slot
			if index >= a.audit_matching.len { break }
			row_index := a.audit_matching[index]
			row := a.audit_snapshot.rows[row_index]
			children << ui2.Element{
				...ui2.button(software_row_actions[slot], row.status + ': ' + row.id, ui2.rect(14, f64(128 + slot * 30), 236, 28),
					ui2.BoxStyle{ bg: if row_index == a.audit_selected { settings_choice_bg } else { body_panel }, radius: 3 },
					ui2.TextStyle{ color: body_text, size: 12, align: .left })
				key: workflow_owned_text_key
			}
		}
		if a.details_page >= 0 && a.details_page < a.details_pages.len {
			software_page_lines(mut children, a.details_pages[a.details_page].text, 274, 128, width - 288, 18)
			children << software_label(a.details_pages[a.details_page].label, 274, height - 206, width - 288, 28, false)
		}
		children << software_button('software.audit.previous', 'Previous detail', 274, height - 168, 142)
		children << software_button('software.audit.next', 'Next detail', 428, height - 168, 142)
		children << software_button('software.audit.up', 'Previous packages', 14, height - 168, 110)
		children << software_button('software.audit.down', 'Next packages', 136, height - 168, 110)
		children << software_button('software.audit.review', 'Review deployment', 396, height - 130, 174)
	}
	if a.worker == unsafe { nil } { children << software_button('software.audit.reload', 'Reload check', 14, height - 130, 160) }
	a.add_status_footer(mut children, width, height, false)
	return ui2.screen(app_surface, children)
}
