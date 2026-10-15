// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

fn (mut a SoftwareApp) clear_health() {
	a.clear_details()
	a.health_snapshot.close()
	unsafe { a.health_matching.free(); a.health_summary.free() }
	a.health_matching = []int{}
	a.health_summary = ''
	a.health_mode = false; a.health_ready = false
	a.health_selected = -1; a.health_scroll = 0
}

fn (mut a SoftwareApp) read_health() {
	a.clear_health()
	a.health_mode = true
	a.focus = false; a.select_all = false
	mut arguments := ['--json', 'health']
	a.start(arguments, true)
	unsafe { (&array(&arguments)).free() }
	if a.worker != unsafe { nil } {
		a.set_status('Inspecting every installed package, runtime and data dependency…')
	}
}

fn (mut a SoftwareApp) prepare_health_details() {
	a.clear_details()
	if !a.health_ready || a.health_selected < 0 || a.health_selected >= a.health_snapshot.rows.len { return }
	row := a.health_snapshot.rows[a.health_selected]
	a.details_pages = []SoftwareDetailsPage{cap: 8}
	unsafe { a.details_pages.flags |= .noslices }
	mut values := ['Package ID: ' + row.id, 'Name: ' + row.name, 'Installed version: ' + row.version,
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

fn (mut a SoftwareApp) load_health() {
	mut report := pkgprotocol.decode_health(editor_bytes_text(a.output)) or {
		unsafe { err.free() }
		a.set_status('Invalid or incomplete health report. Reload before reviewing repairs.')
		return
	}
	a.health_snapshot.close()
	a.health_snapshot = report
	a.health_matching.clear()
	unsafe { a.health_matching.flags |= .noslices }
	// Show the problems first without changing the report's canonical ID order.
	for issues in [true, false]! {
		for index, row in report.rows { if (row.issue != '') == issues { a.health_matching << index } }
	}
	a.health_ready = true
	a.health_selected = if a.health_matching.len == 0 { -1 } else { a.health_matching[0] }
	a.health_scroll = 0
	count := report.rows.len.str()
	issues := report.rows.filter(it.issue != '')
	damaged := issues.len.str()
	number := report.generation.str()
	unsafe { a.health_summary.free() }
	a.health_summary = 'Generation ${number} · ${count} packages inspected · ${damaged} with issues'
	unsafe { count.free(); damaged.free(); number.free(); (&array(&issues)).free() }
	a.prepare_health_details()
	a.set_status('Integrity observation only: each row describes its own tree and first issue. Trust, policy and dependencies still gate launch. Repair reviews current state again; it retains personal data.')
}

fn (mut a SoftwareApp) handle_health(event_id string) {
	match event_id {
		'software.health.back' { a.clear_health() }
		'software.health.reload' { a.read_health() }
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
					a.prepare_health_details()
					return
				}
			}
		}
	}
}

fn (mut a SoftwareApp) build_health(width int, height int) ui2.Element {
	mut children := frame_elements(32)
	children << software_label('Installed software health', 14, 8, width - 202, 28, false)
	children << software_button('software.health.back', 'Back to packages', width - 174, 8, 160)
	children << software_label(a.health_summary, 14, 46, width - 28, 36, false)
	if a.health_ready {
		for slot in 0 .. a.page_rows {
			index := a.health_scroll + slot
			if index >= a.health_matching.len { break }
			row_index := a.health_matching[index]
			row := a.health_snapshot.rows[row_index]
			children << ui2.button(software_row_actions[slot], row.id, ui2.rect(14, f64(90 + slot * 30), 236, 28),
				ui2.BoxStyle{ bg: if row_index == a.health_selected { settings_choice_bg } else { body_panel }, radius: 3 },
				ui2.TextStyle{ color: body_text, size: 12, align: .left })
		}
		if a.details_page >= 0 && a.details_page < a.details_pages.len {
			page := a.details_pages[a.details_page]
			children << ui2.label('', page.text, ui2.rect(274, 90, f64(width - 288), f64(height - 304)),
				ui2.TextStyle{ color: body_text, size: 12, lines: 14 })
			children << software_label(page.label, 274, height - 214, width - 288, 28, false)
			children << software_button('software.health.previous', 'Previous detail', 274, height - 176, 142)
			children << software_button('software.health.next', 'Next detail', 428, height - 176, 142)
		}
		children << software_button('software.health.up', 'Previous packages', 14, height - 176, 110)
		children << software_button('software.health.down', 'Next packages', 136, height - 176, 110)
		if a.health_snapshot.rows.len > 0 { children << software_button('software.health.repair', 'Review repairs', 396, height - 138, 160) }
	}
	children << software_button('software.health.reload', 'Reload report', 274, height - 138, 110)
	a.add_status_footer(mut children, width, height, false)
	return ui2.screen(app_surface, children)
}
