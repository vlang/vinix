// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.pkgprotocol

fn software_audit_matches(row pkgprotocol.DeploymentAuditRow, query string) bool {
	if query == '' { return true }
	for value in [row.id, row.status, row.expected_version, row.installed_version]! {
		text := software_search_lower(value)
		found := text.contains(query)
		unsafe { text.free() }
		if found { return true }
	}
	for field in row.differences {
		text := software_search_lower(field)
		found := text.contains(query)
		unsafe { text.free() }
		if found { return true }
	}
	return false
}

fn (mut a SoftwareApp) keep_audit_selection_visible() {
	a.audit_scroll = 0
	for position, index in a.audit_matching {
		if index == a.audit_selected {
			size := if a.page_rows > 0 { a.page_rows } else { 1 }
			a.audit_scroll = position / size * size
			return
		}
	}
}

fn (mut a SoftwareApp) filter_deployment_audit() {
	a.audit_matching.clear()
	unsafe { a.audit_matching.flags |= .noslices }
	query := software_search_lower(if a.audit_query.len == 0 { '' } else { editor_bytes_text(a.audit_query) })
	defer { unsafe { query.free() } }
	// Indices retain the report's canonical row identities. Differences stay
	// first while search and the optional differences-only view are combined.
	for different in [true, false]! {
		if !different && a.audit_differences_only { continue }
		for index, row in a.audit_snapshot.rows {
			if (row.status != 'match') == different && software_audit_matches(row, query) { a.audit_matching << index }
		}
	}
	previous := a.audit_selected
	if a.audit_selected !in a.audit_matching {
		a.audit_selected = if a.audit_matching.len == 0 { -1 } else { a.audit_matching[0] }
	}
	a.keep_audit_selection_visible()
	if previous != a.audit_selected || a.details_pages.len == 0 { a.prepare_deployment_audit_details() }
	visible := a.audit_matching.len.str(); total := a.audit_snapshot.rows.len.str()
	unsafe { a.audit_results.free() }
	a.audit_results = 'Showing ' + visible + ' of ' + total
	unsafe { visible.free(); total.free() }
}

fn (mut a SoftwareApp) audit_paste_input(input string) {
	if a.worker != unsafe { nil } || !a.audit_ready || !a.audit_focus || input == '' { return }
	if !software_search_paste(mut a.audit_query, input, a.audit_select_all) {
		a.set_status(software_search_input_error)
		return
	}
	a.audit_select_all = false
	a.filter_deployment_audit()
}

fn (mut a SoftwareApp) audit_key_input(input string) {
	if input == '\x1b' {
		if a.audit_focus { a.audit_focus = false; a.audit_select_all = false }
		else { a.handle_deployment_audit('software.audit.back') }
		return
	}
	if a.worker != unsafe { nil } || !a.audit_ready || !a.audit_focus { return }
	match input {
		'\x01' { a.audit_select_all = true }
		'\x7f', '\x08' {
			console_backspace(mut a.audit_query, a.audit_select_all)
			a.audit_select_all = false
			a.filter_deployment_audit()
		}
		'\r', '\n' { a.audit_focus = false; a.audit_select_all = false }
		else { a.audit_paste_input(input) }
	}
}
