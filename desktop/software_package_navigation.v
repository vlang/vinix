// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (a &SoftwareApp) catalog_browsable() bool {
	return a.package_screen_active() && a.worker == unsafe { nil } && a.review == '' && a.launch_request == ''
}

fn (mut a SoftwareApp) keep_catalog_selection_visible() {
	position := a.matching.index(a.selected)
	if position < 0 { return }
	if position < a.scroll { a.scroll = position }
	if position >= a.scroll + a.page_rows { a.scroll = position - a.page_rows + 1 }
}

fn (mut a SoftwareApp) select_catalog_package(step int) {
	if a.matching.len == 0 { a.selected = -1; a.scroll = 0; return }
	mut position := a.matching.index(a.selected)
	if position < 0 { position = 0 } else { position += step }
	if position < 0 { position = 0 }
	if position >= a.matching.len { position = a.matching.len - 1 }
	a.selected = a.matching[position]
	a.keep_catalog_selection_visible()
}

fn (mut a SoftwareApp) open_catalog_browser() {
	if !a.catalog_browsable() { return }
	a.catalog_browser_mode = true
	a.catalog_browser_notice = false
	a.focus = false; a.select_all = false
	a.select_catalog_package(0)
}

fn (mut a SoftwareApp) close_catalog_browser() {
	a.catalog_browser_mode = false
	a.focus = false; a.select_all = false
	a.keep_catalog_selection_visible()
}

fn (mut a SoftwareApp) handle_catalog_browser(action string) {
	match action {
		'software.catalog.back' { a.close_catalog_browser() }
		'software.search' { a.focus = true }
		'software.catalog.filter' {
			a.catalog_browser_notice = false
			a.filter = (a.filter + 1) % 3
			a.filter_rows()
			if a.filter == 2 && a.update_error != '' { a.set_update_status(); a.catalog_browser_notice = true }
		}
		'software.catalog.previous', 'software.catalog.next' {
			a.focus = false; a.select_all = false
			a.select_catalog_package(if action == 'software.catalog.next' { 1 } else { -1 })
		}
		'software.details' { a.open_details() }
		else {} // Browsing cannot start a service call, review or application.
	}
}

fn (a &SoftwareApp) build_catalog_browser(width int, height int) ui2.Element {
	mut children := frame_elements(9)
	button_width := if width >= 180 { (width - 40) / 2 } else { width - 28 }
	children << software_button('software.catalog.back', 'Back', 14, 8, button_width)
	if width < 180 || height < 220 {
		children << software_label('Enlarge to browse packages.', 14, 46, width - 28, 54, false)
		return ui2.screen(app_surface, children)
	}
	children << software_button('software.catalog.filter', match a.filter { 1 { 'Installed' } 2 { 'Updates' } else { 'Catalog' } },
		width - 14 - button_width, 8, button_width)
	children << console_field('software.search', editor_bytes_text(a.query), 14, 46, width - 28, a.focus)
	children << software_button('software.catalog.previous', 'Previous', 14, 84, button_width)
	children << software_button('software.catalog.next', 'Next', width - 14 - button_width, 84, button_width)
	position := a.matching.index(a.selected)
	if position >= 0 && a.selected >= 0 && a.selected < a.rows.len {
		number := (position + 1).str(); total := a.matching.len.str()
		children << software_label(number + ' / ' + total, 14, 118, width - 28, 24, true)
		unsafe { number.free(); total.free() }
		children << software_label(if a.catalog_browser_notice { a.status } else { a.rows[a.selected].name }, 14, 146, width - 28, 36, false)
		children << software_button('software.details', 'Details', 14, height - 36, width - 28)
	} else {
		children << software_label('No matches', 14, 118, width - 28, 24, false)
		children << software_label(if a.catalog_browser_notice { a.status } else { 'Change search or filter. Back returns to catalog status and reload.' }, 14, 146, width - 28, height - 154, false)
	}
	return ui2.screen(app_surface, children)
}

fn (a &SoftwareApp) package_screen_active() bool {
	return !a.deployment_mode && !a.mirror_mode && !a.repository_mode && !a.policy_mode
		&& !a.data_mode && !a.launch_mode && !a.health_mode && !a.cleanup_mode
		&& !a.audit_mode && !a.snapshot_mode && !a.window_mode && a.terminal_app == unsafe { nil }
}

fn (a &SoftwareApp) package_review_running() bool {
	return a.package_screen_active() && a.worker != unsafe { nil } && a.worker_review
		&& a.review in ['install', 'remove', 'upgrade', 'repair', 'rollback']!
}

fn (a &SoftwareApp) package_review_readable() bool {
	return a.worker == unsafe { nil } && a.review_ready
		&& ((a.package_screen_active() && a.review in ['install', 'remove', 'upgrade', 'repair', 'rollback']!)
			|| (a.deployment_mode && a.review == 'deploy' && a.deployment_pending != ''))
}

fn (a &SoftwareApp) package_plan_values(mut values []string) {
	values << 'Read-only package plan. Reading does not approve a transaction.'.clone()
	values << 'Operation: ' + a.review_snapshot.operation
	values << 'Target architecture: ' + a.review_snapshot.architecture
	values << 'Review fingerprint: ' + a.review_snapshot.fingerprint
	software_details_count(mut values, 'Active generation: ', a.review_snapshot.generation)
	if a.review == 'rollback' { software_details_count(mut values, 'Restore from generation: ', a.review_snapshot.target_generation) }
	software_details_count(mut values, 'Operation arguments: ', u64(a.review_snapshot.names.len))
	software_details_count(mut values, 'Requested application roots: ', u64(a.review_snapshot.requested.len))
	software_details_count(mut values, 'Packages including dependencies and removals: ', u64(a.review_snapshot.rows.len))
	software_details_count(mut values, 'Required disk space (bytes): ', a.review_snapshot.disk_needed)
	software_details_count(mut values, 'Available disk space (bytes): ', a.review_snapshot.disk_available)
	software_details_count(mut values, 'Reserved disk space (bytes): ', a.review_snapshot.disk_reserve)
	if a.deployment_pending != '' {
		path := software_failure_text(a.deployment_pending)
		values << 'Frozen deployment file: ' + path
		unsafe { path.free() }
	}
	values << match a.review {
		'deploy' { 'Deployment replaces the installed application set with the reviewed roots and dependencies, including listed removals.'.clone() }
		'rollback' { 'Rollback restores the previous package set in a new generation and retains the current set so it can be restored again.'.clone() }
		'repair' { 'Repair preserves installed versions, permissions and application roots. Packages marked repair are rebuilt from authenticated payloads.'.clone() }
		'remove' { 'Uninstall removes the reviewed applications and unused dependencies.'.clone() }
		else { 'The transaction applies this exact reviewed package set, including retained packages, runtime changes and removals.'.clone() }
	}
	values << 'Personal application data stays on disk. Package rollback restores packages, not personal data.'.clone()
	item := a.review_read_item
	if item >= 0 && item < a.review_snapshot.names.len {
		software_details_count(mut values, 'Operation argument number: ', u64(item + 1))
		values << 'Frozen operation argument: ' + a.review_snapshot.names[item]
	} else if item >= a.review_snapshot.names.len && item < a.review_snapshot.names.len + a.review_snapshot.rows.len {
		software_details_count(mut values, 'Package number: ', u64(item - a.review_snapshot.names.len + 1))
		row := software_review_row(a.review_snapshot.rows[item - a.review_snapshot.names.len])
		if !software_details_row_valid(row) { values << 'This package has invalid UTF-8 or oversized metadata. Review again before confirming.'.clone() }
	} else { values << 'No item selected. Next item visits operation arguments, then every package. An empty plan still shows its complete scope.'.clone() }
	values << 'Use item navigation to inspect every operation argument and package, including publishers, permissions, licenses, proprietary/firmware declarations and runtimes.'.clone()
	values << 'Return to the full review to confirm or cancel. Confirmation uses the frozen intent and repeats service validation.'.clone()
}

fn (mut a SoftwareApp) prepare_package_plan() {
	index := a.review_read_item - a.review_snapshot.names.len
	if index >= 0 && index < a.review_snapshot.rows.len {
		row := software_review_row(a.review_snapshot.rows[index])
		if software_details_row_valid(row) {
			action := a.review_snapshot.rows[index].action
			a.prepare_details_context(row, if a.review == 'repair' && action == 'update' { 'repair' } else { action }, true, true)
			return
		}
	}
	a.prepare_details_context(SoftwareRow{}, '', true, true)
}

fn (mut a SoftwareApp) stop_package_review() {
	// Only unaccepted read-only proposals can be killed. Catalog refreshes,
	// approved transactions and other Software subflows keep their own lifecycle.
	if !a.package_review_running() { return }
	if a.worker.is_alive() { a.worker.signal_kill(); a.worker.wait() }
	a.retire_worker(); a.worker_review = false
	a.clear_review(); a.output.clear(); a.output_truncated = false
	a.focus = false; a.select_all = false
	a.set_status('Package review stopped. No changes were started. Review the operation again to continue.')
}

fn (a &SoftwareApp) build_packages_compact(width int, height int) ui2.Element {
	mut children := frame_elements(9)
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil } && !a.details_mode
	readable := a.package_review_readable() && !a.details_mode
	browsable := a.catalog_browsable() && !a.details_mode
	children << software_label('Software', 14, 8, width - 28, 28, false)
	button_width := if width > 202 { 174 } else { width - 28 }
	if a.details_mode {
		children << software_button('software.details.back', if a.review != '' { 'Back to review' } else { 'Back to catalog' }, 14, 46, button_width)
	} else if a.package_review_running() {
		children << software_button('software.review.stop', 'Stop review', 14, 46, button_width)
	} else if a.verification_running() {
		children << software_button('software.verify.stop', 'Stop verifying', 14, 46, button_width)
	} else if a.worker == unsafe { nil } {
		children << software_button(if a.review != '' { 'software.cancel' } else { 'software.reload' },
			if a.review != '' { 'Cancel review' } else { 'Reload catalog' }, 14, 46, button_width)
	} else {
		children << software_label(if a.worker_view { 'Reading the software catalog…' } else { 'Wait for the operation to finish.' }, 14, 46, width - 28, 28, false)
	}
	if readable { children << software_button('software.report.read', 'Read plan', 14, 84, button_width) }
	if browsable { children << software_button('software.catalog.browse', 'Browse catalog', 14, 84, button_width) }
	if available { children << software_button('software.failure', 'Failure details', 14, if readable || browsable { 122 } else { 84 }, button_width) }
	progress := a.progress_seen && height >= 240
	if progress { children << a.progress_bar(width, height) }
	minimum := if (readable || browsable) && available { 160 } else if readable || browsable || available { 122 } else { 84 }
	footer := height - if progress { 88 } else { 98 }
	y := if footer > minimum { footer } else { minimum }
	children << software_label(a.status, 14, y, width - 28, if height > y + 8 { height - y - 8 } else { 1 }, false)
	return ui2.screen(app_surface, children)
}
