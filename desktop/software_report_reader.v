// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (mut a SoftwareApp) prepare_report_reader() {
	a.details_compact_pages = []SoftwareFailurePage{cap: 16}
	unsafe { a.details_compact_pages.flags |= .noslices }
	for index, page in a.details_pages {
		software_failure_paginate(mut a.details_compact_pages, page.text, 12, 3, index)
	}
	software_failure_labels(mut a.details_compact_pages)
}

fn (mut a SoftwareApp) open_report_reader() {
	if a.worker != unsafe { nil } { return }
	if a.launch_mode {
		a.launch_read_file = a.launch_file_selected
		a.prepare_launch_details()
	}
	if a.mirror_review_readable() { a.prepare_mirror_details() }
	if a.package_review_readable() {
		a.review_read_item = if a.review_selected >= 0 && a.review_selected < a.review_snapshot.rows.len { a.review_snapshot.names.len + a.review_selected } else { -1 }
		a.prepare_package_plan()
	}
	if a.details_pages.len == 0
		|| !((a.health_mode && a.health_ready) || (a.audit_mode && a.audit_ready)
			|| (a.snapshot_mode && a.snapshot_ready) || (a.cleanup_mode && a.cleanup_ready)
			|| (a.repository_mode && a.repository_review_ready)
			|| (a.data_mode && a.data_ready && a.administration_required) || a.launch_mode
			|| a.mirror_review_readable() || a.package_review_readable()) { return }
	a.report_reader_mode = true
	// Drafts and frozen export forms keep their focus/selection behind the modal.
	if !a.launch_mode && !a.mirror_mode && !a.package_review_readable() { a.focus = false; a.select_all = false }
	a.health_focus = false; a.health_select_all = false
	a.audit_focus = false; a.audit_select_all = false
	a.anchor_details_compact_page()
}

fn (a &SoftwareApp) report_has_packages() bool {
	return (a.health_mode && a.health_matching.len > 0) || (a.audit_mode && a.audit_matching.len > 0)
		|| (a.data_mode && a.data_pending == '' && a.data_status.rows.len > 0)
		|| (a.launch_mode && a.launch_documents.len > 0)
		|| (a.package_review_readable() && a.review_snapshot.names.len + a.review_snapshot.rows.len > 0)
}

fn (mut a SoftwareApp) report_select_package(step int) {
	compact := a.details_compact_mode
	if a.package_review_readable() {
		position := a.review_read_item + step
		if position < 0 || position >= a.review_snapshot.names.len + a.review_snapshot.rows.len { return }
		a.review_read_item = position
		a.prepare_package_plan()
	} else if a.launch_mode {
		position := a.launch_read_file + step
		if position < 0 || position >= a.launch_documents.len { return }
		a.launch_read_file = position
		a.prepare_launch_details()
	} else if a.data_mode {
		if a.data_pending != '' { return }
		position := a.data_selected + step
		if position < 0 || position >= a.data_status.rows.len { return }
		a.data_selected = position
		a.keep_data_selection_visible()
		a.prepare_personal_data_details()
	} else if a.health_mode {
		position := a.health_matching.index(a.health_selected) + step
		if position < 0 || position >= a.health_matching.len { return }
		a.health_selected = a.health_matching[position]
		a.keep_health_selection_visible()
		a.prepare_health_details()
	} else if a.audit_mode {
		position := a.audit_matching.index(a.audit_selected) + step
		if position < 0 || position >= a.audit_matching.len { return }
		a.audit_selected = a.audit_matching[position]
		a.keep_audit_selection_visible()
		a.prepare_deployment_audit_details()
	} else { return }
	// Preparing a different row retires both page caches and their modal state.
	a.report_reader_mode = true
	a.details_compact_mode = compact
}

fn (mut a SoftwareApp) handle_report_reader(action string) {
	if a.worker != unsafe { nil } { return }
	match action {
		'software.report.back' {
			if a.launch_mode { a.clear_details(); a.launch_read_file = -1 }
			else if a.mirror_mode { a.clear_details() }
			else if a.package_review_readable() { a.clear_details(); a.review_read_item = -1 }
			else { a.report_reader_mode = false; a.details_compact_mode = false }
		}
		'software.report.previous', 'software.report.next' {
			step := if action == 'software.report.next' { 1 } else { -1 }
			if a.details_compact_mode {
				a.anchor_details_compact_page()
				next := a.details_compact_page + step
				if next >= 0 && next < a.details_compact_pages.len {
					a.details_compact_page = next; a.details_page = a.details_compact_pages[next].source_page
				}
			} else {
				next := a.details_page + step
				if next >= 0 && next < a.details_pages.len { a.details_page = next }
			}
		}
		'software.report.package.previous' { a.report_select_package(-1) }
		'software.report.package.next' { a.report_select_package(1) }
		else {}
	}
}

fn (mut a SoftwareApp) report_reader_key_input(input string) {
	match input {
		'\x1b' { a.handle_report_reader('software.report.back') }
		'\x1b[D', '\x1b[5~' { a.handle_report_reader('software.report.previous') }
		'\x1b[C', '\x1b[6~' { a.handle_report_reader('software.report.next') }
		'\x1b[A', '\x1b[Z' { a.handle_report_reader('software.report.package.previous') }
		'\x1b[B', '\t' { a.handle_report_reader('software.report.package.next') }
		else {}
	}
}

fn (mut a SoftwareApp) build_report_reader(width int, height int) ui2.Element {
	a.details_compact_mode = width < 640 || height < 610
	a.anchor_details_compact_page()
	mut children := frame_elements(if a.details_compact_mode { 10 } else { 24 })
	content_width := if width > 28 { width - 28 } else { 1 }
	title := if a.package_review_readable() { 'Package plan' } else if a.mirror_mode { 'Export review' } else if a.launch_mode { 'Launch draft' } else if a.data_mode { 'Personal data' } else if a.repository_mode { 'Repository trust' } else if a.cleanup_mode { 'Cleanup review' } else if a.health_mode { 'Health details' } else if a.audit_mode { 'Deployment check' } else { 'Saved deployment' }
	if a.details_compact_mode {
		back_width := if content_width >= 56 { 56 } else { content_width }
		children << software_button('software.report.back', 'Back', if width > back_width + 28 { width - back_width - 14 } else { 14 }, 8, back_width)
		if width < 180 || height < 220 {
			children << software_label('Enlarge to read the report.', 14, 46, content_width, 28, false)
			return ui2.screen(app_surface, children)
		}
		children << software_label(title, 14, 46, content_width, 28, false)
		button_width := (width - 42) / 2
		if a.report_has_packages() {
			children << software_button('software.report.package.previous', if a.launch_mode { 'Prev file' } else { 'Prev item' }, 14, 80, button_width)
			children << software_button('software.report.package.next', if a.launch_mode { 'Next file' } else { 'Next item' }, width - 14 - button_width, 80, button_width)
		} else { children << software_label('Recorded metadata', 14, 80, content_width, 28, false) }
		if a.details_compact_page >= 0 && a.details_compact_page < a.details_compact_pages.len {
			page := a.details_compact_pages[a.details_compact_page]
			children << software_label(page.label, 14, 8, width - back_width - 42, 28, false)
			software_page_lines(mut children, page.text, 14, 118, content_width, 18)
		}
		children << software_button('software.report.previous', 'Previous', 14, height - 36, button_width)
		children << software_button('software.report.next', 'Next', width - 14 - button_width, height - 36, button_width)
	} else {
		children << software_label(title, 14, 8, width - 202, 28, false)
		children << software_button('software.report.back', 'Back to report', width - 174, 8, 160)
		if a.report_has_packages() {
			children << software_button('software.report.package.previous', if a.launch_mode { 'Previous file' } else if a.package_review_readable() { 'Previous item' } else { 'Previous package' }, 14, 46, 160)
			children << software_button('software.report.package.next', if a.launch_mode { 'Next file' } else if a.package_review_readable() { 'Next item' } else { 'Next package' }, 186, 46, 160)
		}
		if a.details_page >= 0 && a.details_page < a.details_pages.len {
			page := a.details_pages[a.details_page]
			software_page_lines(mut children, page.text, 14, 94, content_width, 20)
			children << software_label(page.label, 238, height - 138, width - 252, 28, false)
		}
		children << software_button('software.report.previous', 'Previous', 14, height - 138, 100)
		children << software_button('software.report.next', 'Next', 126, height - 138, 100)
		children << software_label(if a.package_review_readable() { 'Read-only package plan. Return to the full review before confirming or cancelling the frozen operation.' }
			else if a.mirror_mode { 'Read-only export proposal. Return to the full review before inspecting path parts and packages, cancelling or confirming.' }
			else if a.launch_mode { 'Read-only draft. Return to launch options before editing arguments or grants, changing the working folder or running.' }
			else if a.data_mode { 'Read-only details. Return to personal data before reloading, reviewing, cancelling or confirming deletion.' }
			else if a.repository_mode { 'Read-only details. Return to the full trust review before cancelling, reviewing URL parts or confirming the change.' }
			else if a.cleanup_mode { 'Read-only review. Return to cleanup before reloading or confirming deletion.' }
			else { 'Read-only details. Return to the report before reloading, saving, exporting or reviewing changes.' }, 14, height - 98, content_width, 90, false)
	}
	return ui2.screen(app_surface, children)
}
