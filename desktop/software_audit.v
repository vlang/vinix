// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

fn (mut a SoftwareApp) clear_deployment_audit_report() {
	a.clear_details()
	a.audit_snapshot.close()
	unsafe { a.audit_summary.free() }
	a.audit_summary = ''
	a.audit_ready = false; a.audit_selected = -1; a.audit_scroll = 0
}

fn (mut a SoftwareApp) clear_deployment_audit() {
	a.clear_deployment_audit_report()
	unsafe { a.audit_path.free() }
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
	a.audit_selected = if report.rows.len > 0 { 0 } else { -1 }
	mut differences := 0
	for index, row in report.rows {
		if row.status != 'match' {
			if differences == 0 { a.audit_selected = index }
			differences++
		}
	}
	if a.audit_selected >= 0 && a.page_rows > 0 { a.audit_scroll = a.audit_selected / a.page_rows * a.page_rows }
	count := report.rows.len.str(); changed := differences.str(); generation := report.generation.str()
	a.audit_summary = 'Generation ' + generation + ' · ' + count + ' packages · ' + changed + ' differences'
	unsafe { count.free(); changed.free(); generation.free() }
	a.prepare_deployment_audit_details()
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
		'software.audit.down' { if a.audit_scroll + a.page_rows < a.audit_snapshot.rows.len { a.audit_scroll += a.page_rows } }
		else {
			for slot, action in software_row_actions {
				if event_id == action && a.audit_ready && a.audit_scroll + slot < a.audit_snapshot.rows.len {
					a.audit_selected = a.audit_scroll + slot
					a.prepare_deployment_audit_details()
					return
				}
			}
		}
	}
}

fn (mut a SoftwareApp) build_deployment_audit_compact(width int, height int) ui2.Element {
	mut children := frame_elements(4)
	children << software_button(if a.worker == unsafe { nil } { 'software.audit.back' } else { 'software.audit.stop' },
		if a.worker == unsafe { nil } { 'Back to deployment' } else { 'Stop check' }, 14, 8, if width > 188 { 174 } else { width - 28 })
	children << software_label('Installed deployment check', 14, 46, width - 28, 28, false)
	children << software_label('Enlarge this window to inspect package differences and deployment details.', 14, 80, width - 28, if height > 140 { 60 } else { 28 }, false)
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) build_deployment_audit(width int, height int) ui2.Element {
	a.page_rows = (height - 300) / 30
	if a.page_rows > software_row_actions.len { a.page_rows = software_row_actions.len }
	mut children := frame_elements(40)
	children << software_label('Installed deployment check', 14, 8, width - 202, 28, false)
	children << software_button(if a.worker == unsafe { nil } { 'software.audit.back' } else { 'software.audit.stop' },
		if a.worker == unsafe { nil } { 'Back to deployment' } else { 'Stop check' }, width - 188, 8, 174)
	children << software_label(a.audit_summary, 14, 46, width - 28, 36, false)
	if a.audit_ready {
		if a.audit_snapshot.rows.len == 0 { children << software_label('No package metadata in either set.', 14, 94, 236, 72, false) }
		for slot in 0 .. a.page_rows {
			index := a.audit_scroll + slot
			if index >= a.audit_snapshot.rows.len { break }
			row := a.audit_snapshot.rows[index]
			children << ui2.Element{
				...ui2.button(software_row_actions[slot], row.status + ': ' + row.id, ui2.rect(14, f64(94 + slot * 30), 236, 28),
					ui2.BoxStyle{ bg: if index == a.audit_selected { settings_choice_bg } else { body_panel }, radius: 3 },
					ui2.TextStyle{ color: body_text, size: 12, align: .left })
				key: workflow_owned_text_key
			}
		}
		if a.details_page >= 0 && a.details_page < a.details_pages.len {
			children << ui2.label('', a.details_pages[a.details_page].text, ui2.rect(274, 94, f64(width - 288), f64(height - 300)),
				ui2.TextStyle{ color: body_text, size: 12, lines: 14 })
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
