// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.utf8
import ui2

struct SoftwareDetailsPage {
	section int
	title string
	text string
mut:
	label string
}

const software_details_actions = ['software.details.overview', 'software.details.description',
	'software.details.publisher', 'software.details.permissions', 'software.details.license', 'software.details.diagnostics']
const software_details_titles = ['Overview', 'Description', 'Publisher', 'Permissions', 'License', 'Diagnostics']

fn (mut a SoftwareApp) clear_details() {
	unsafe {
		for page in a.details_pages { page.title.free(); page.text.free(); page.label.free() }
		(&array(&a.details_pages)).free()
		for page in a.details_compact_pages { page.text.free(); page.label.free() }
		(&array(&a.details_compact_pages)).free()
	}
	a.details_pages = []SoftwareDetailsPage{}
	a.details_compact_pages = []SoftwareFailurePage{}
	a.details_compact_page = 0; a.details_compact_mode = false
	a.details_mode = false; a.details_review = false
	a.report_reader_mode = false
	a.details_section = 0; a.details_page = 0
	for index in 0 .. 6 { a.details_starts[index] = -1 }
}

fn software_details_text_valid(value string, limit int) bool {
	return value.len <= limit && utf8.validate_str(value)
}

fn software_details_row_valid(row SoftwareRow) bool {
	if row.id == '' || row.name == '' || row.permissions.len > 5 || row.installed_permissions.len > 5
		|| row.installed_window_protocol < 0 || row.installed_window_protocol > 2 { return false }
	for value in [row.id, row.runtime, row.repository]! { if !software_details_text_valid(value, 128) { return false } }
	for value in [row.name, row.installed_name, row.license]! { if !software_details_text_valid(value, 256) { return false } }
	for value in [row.description, row.diagnostic]! { if !software_details_text_valid(value, 4096) { return false } }
	for value in [row.version, row.installed_version]! { if !software_details_text_valid(value, 29) { return false } }
	for value in [row.kind, row.installed_kind, row.architecture, row.update_action]! { if !software_details_text_valid(value, 16) { return false } }
	if !software_details_text_valid(row.public_key, 64) { return false }
	for value in row.permissions { if !software_details_text_valid(value, 16) { return false } }
	for value in row.installed_permissions { if !software_details_text_valid(value, 16) { return false } }
	return true
}

// Keep control bytes visible without allowing them to alter the page layout.
// Input has already been bounded and checked for UTF-8 before page preparation.
fn software_details_text(value string) string {
	mut bytes := []u8{cap: value.len * 4}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	for byte in value {
		if byte < 32 || byte == 127 {
			bytes << `\\`; bytes << `x`
			bytes << '0123456789abcdef'[byte >> 4]; bytes << '0123456789abcdef'[byte & 15]
		} else { bytes << byte }
	}
	return bytes.bytestr()
}

fn (mut a SoftwareApp) details_add_page(section int, lines []string) {
	if a.details_starts[section] < 0 { a.details_starts[section] = a.details_pages.len }
	page := SoftwareDetailsPage{ section: section, title: software_details_titles[section].clone(), text: lines.join('\n') }
	pointer := unsafe { &page }
	unsafe { a.details_pages.push_many(pointer, 1) }
}

fn (mut a SoftwareApp) details_values(section int, values []string) {
	a.details_values_columns(section, values, 48)
}

fn (mut a SoftwareApp) details_values_columns(section int, values []string, columns int) {
	mut lines := []string{cap: 14}
	unsafe { lines.flags |= .noslices }
	defer { software_policy_free_lines(mut lines) }
	for value in values {
		text := software_details_text(value)
		mut start := 0
		for start < text.len {
			mut end := if start + columns < text.len { start + columns } else { text.len }
			for end > start && end < text.len && text[end] & 0xc0 == 0x80 { end-- }
			chunk := unsafe { tos(text.str + start, end - start) }
			lines << (if start == 0 { '• ' } else { '  ' }) + chunk
			start = end
			if lines.len == 14 {
				a.details_add_page(section, lines)
				for line in lines { unsafe { line.free() } }
				lines.clear()
			}
		}
		unsafe { text.free() }
	}
	if lines.len > 0 { a.details_add_page(section, lines) }
}

fn software_details_count(mut values []string, label string, count u64) {
	number := count.str()
	values << label + number
	unsafe { number.free() }
}

fn (mut a SoftwareApp) prepare_details(row SoftwareRow, action string, reviewing bool) {
	a.prepare_details_context(row, action, reviewing, false)
}

fn (mut a SoftwareApp) prepare_details_context(row SoftwareRow, action string, reviewing bool, plan bool) {
	a.clear_details()
	a.details_review = reviewing
	a.details_pages = []SoftwareDetailsPage{cap: 32}
	unsafe { a.details_pages.flags |= .noslices }
	mut general := []string{cap: 24}
	unsafe { general.flags |= .noslices }
	if plan {
		a.package_plan_values(mut general)
		if row.id == '' {
			a.details_values(0, general); software_policy_free_lines(mut general)
			a.finish_details(true)
			return
		}
	}
	general << if reviewing { 'Facts from the reviewed package set.'.clone() } else { 'Facts describe the selected catalog/update version; installed launch fields appear separately.'.clone() }
	general << 'Package ID: ' + row.id
	general << 'Name: ' + row.name
	general << 'Version shown: ' + row.version
	general << 'Installed version: ' + if row.installed_version == '' { 'Not installed' } else { row.installed_version }
	general << 'Architecture: ' + row.architecture
	general << 'Kind: ' + row.kind
	general << 'Runtime ID: ' + if row.runtime == '' { 'None declared' } else { row.runtime }
	if reviewing {
		general << 'Reviewed operation: ' + a.review_snapshot.operation
		general << 'Package action: ' + action
		general << 'Target role: ' + if row.requested { 'Requested application' } else { 'Dependency or removed package' }
		software_details_count(mut general, 'Active generation: ', a.review_snapshot.generation)
		if a.review_snapshot.target_generation != 0 { software_details_count(mut general, 'Restore from generation: ', a.review_snapshot.target_generation) }
	} else {
		general << 'Installed role: ' + if row.installed_version == '' { 'Not installed' } else if row.requested { 'Requested application' } else { 'Dependency/runtime' }
		general << 'Update status: ' + if a.update_error != '' { 'Updates unavailable; see Diagnostics' } else if row.updatable { row.update_action } else { 'No resolved change' }
		if row.installed_version != '' {
			if row.installed_kind == '' { general << 'Installed launch metadata is unavailable from this service.'.clone() }
			else {
				general << 'Installed name: ' + row.installed_name
				general << 'Installed kind: ' + row.installed_kind
				if row.installed_window_protocol == 0 { general << 'Installed native-window protocol: None'.clone() }
				else { software_details_count(mut general, 'Installed native-window protocol: ', u64(row.installed_window_protocol)) }
			}
		}
	}
	a.details_values(0, general); software_policy_free_lines(mut general)
	mut description := [if row.description == '' { 'No description supplied.'.clone() } else { row.description.clone() }]
	a.details_values(1, description); software_policy_free_lines(mut description)
	mut publisher := ['Displayed package repository: ' + row.repository, 'Publisher key: ' + row.public_key]
	a.details_values(2, publisher); software_policy_free_lines(mut publisher)
	mut permissions := []string{cap: 12}
	if row.permissions.len == 0 { permissions << 'Displayed package permissions: None declared'.clone() }
	for value in row.permissions { permissions << 'Displayed package permission: ' + value }
	if !reviewing && row.installed_version != '' {
		if row.installed_kind == '' { permissions << 'Installed permissions: Unavailable from this service'.clone() }
		else if row.installed_permissions.len == 0 { permissions << 'Installed permissions: None declared'.clone() }
		else { for value in row.installed_permissions { permissions << 'Installed permission: ' + value } }
	}
	a.details_values(3, permissions); software_policy_free_lines(mut permissions)
	mut licensing := ['License: ' + row.license, 'Proprietary payload: ' + if row.proprietary { 'Yes' } else { 'No' },
		'Firmware payload: ' + if row.firmware { 'Yes' } else { 'No' }]
	a.details_values(4, licensing); software_policy_free_lines(mut licensing)
	mut diagnostics := []string{cap: 8}
	if reviewing {
		software_details_count(mut diagnostics, 'Required disk space (bytes): ', a.review_snapshot.disk_needed)
		software_details_count(mut diagnostics, 'Available disk space (bytes): ', a.review_snapshot.disk_available)
		software_details_count(mut diagnostics, 'Reserved disk space (bytes): ', a.review_snapshot.disk_reserve)
		if !plan && a.deployment_pending != '' { diagnostics << 'Deployment file: ' + a.deployment_pending }
		if a.mirror_pending != '' { diagnostics << 'Export destination: ' + a.mirror_snapshot.destination }
		if a.mirror_lock_pending != '' { diagnostics << 'Deployment lock: ' + a.mirror_lock_pending }
	} else {
		if row.diagnostic != '' { diagnostics << 'Package diagnostic: ' + row.diagnostic }
		if a.catalog_error != '' { diagnostics << 'Catalog diagnostic: ' + a.catalog_error }
		if a.update_error != '' { diagnostics << 'Update diagnostic: ' + a.update_error }
	}
	if diagnostics.len == 0 { diagnostics << 'No package, catalog or update diagnostics.'.clone() }
	a.details_values(5, diagnostics); software_policy_free_lines(mut diagnostics)
	a.finish_details(plan)
}

fn (mut a SoftwareApp) finish_details(plan bool) {
	mut counts := [6]int{}
	mut numbers := [6]int{}
	mut totals := [6]string{}
	for page in a.details_pages { counts[page.section]++ }
	for section in 0 .. 6 { totals[section] = counts[section].str() }
	overall := a.details_pages.len.str()
	for index in 0 .. a.details_pages.len {
		section := a.details_pages[index].section
		numbers[section]++
		number := if plan { (index + 1).str() } else { numbers[section].str() }
		total := if plan { overall } else { totals[section] }
		a.details_pages[index].label = number + ' of ' + total
		unsafe { number.free() }
	}
	unsafe { overall.free(); for total in totals { total.free() } }
	// Reuse the failure view's UTF-8 pagination and canonical-page anchors.
	// Prepare owned caches once; every redraw borrows its individual lines.
	a.details_compact_pages = []SoftwareFailurePage{cap: 32}
	unsafe { a.details_compact_pages.flags |= .noslices }
	for index, page in a.details_pages {
		software_failure_paginate(mut a.details_compact_pages, page.text, 12, 3, index)
	}
	software_failure_labels(mut a.details_compact_pages)
	a.details_mode = !plan
	if !plan { a.focus = false; a.select_all = false }
}

fn (mut a SoftwareApp) open_details() {
	if a.worker != unsafe { nil } { return }
	reviewing := a.review != ''
	if reviewing && (!a.review_ready || a.review_selected < 0 || a.review_selected >= a.review_snapshot.rows.len) { return }
	if !reviewing && (a.selected < 0 || a.selected >= a.rows.len) { return }
	row := if reviewing { software_review_row(a.review_snapshot.rows[a.review_selected]) } else { a.rows[a.selected] }
	if !software_details_row_valid(row)
		|| (!reviewing && (!software_details_text_valid(a.catalog_error, 4096) || !software_details_text_valid(a.update_error, 4096)))
		|| (reviewing && (!software_details_text_valid(a.deployment_pending, 4096)
			|| !software_details_text_valid(a.mirror_snapshot.destination, 4096) || !software_details_text_valid(a.mirror_lock_pending, 4096))) {
		a.set_status('Package details contain invalid UTF-8 or exceed supported text limits. Reload the catalog or review again.'); return
	}
	action := if reviewing { a.review_snapshot.rows[a.review_selected].action } else { '' }
	a.prepare_details(row, if a.review == 'repair' && action == 'update' { 'repair' } else { action }, reviewing)
}

fn (mut a SoftwareApp) handle_details(action string) {
	if action == 'software.details.back' { a.clear_details(); return }
	if action in ['software.details.previous', 'software.details.next']! {
		if a.details_compact_mode {
			next := a.details_compact_page + if action == 'software.details.next' { 1 } else { -1 }
			if next >= 0 && next < a.details_compact_pages.len {
				canonical := a.details_compact_pages[next].source_page
				if a.details_pages[canonical].section == a.details_section {
					a.details_compact_page = next; a.details_page = canonical
				}
			}
			return
		}
		mut index := a.details_page + if action == 'software.details.next' { 1 } else { -1 }
		for index >= 0 && index < a.details_pages.len {
			if a.details_pages[index].section == a.details_section { a.details_page = index; break }
			index += if action == 'software.details.next' { 1 } else { -1 }
		}
		return
	}
	if action in ['software.details.section.previous', 'software.details.section.next']! {
		step := if action == 'software.details.section.next' { 1 } else { -1 }
		mut section := a.details_section + step
		for section >= 0 && section < software_details_actions.len {
			if a.details_starts[section] >= 0 {
				a.handle_details(software_details_actions[section]); break
			}
			section += step
		}
		return
	}
	for section, event_id in software_details_actions {
		if action == event_id && a.details_starts[section] >= 0 {
			a.details_section = section; a.details_page = a.details_starts[section]
			a.anchor_details_compact_page(); return
		}
	}
}

fn (mut a SoftwareApp) details_key_input(input string) {
	match input {
		'\x1b' { a.clear_details() }
		'\x1b[D', '\x1b[5~' { a.handle_details('software.details.previous') }
		'\x1b[C', '\x1b[6~' { a.handle_details('software.details.next') }
		'\x1b[A', '\x1b[Z' { a.handle_details('software.details.section.previous') }
		'\x1b[B', '\t' { a.handle_details('software.details.section.next') }
		else {}
	}
}

fn (mut a SoftwareApp) anchor_details_compact_page() {
	if a.details_compact_page >= 0 && a.details_compact_page < a.details_compact_pages.len
		&& a.details_compact_pages[a.details_compact_page].source_page == a.details_page { return }
	for index, page in a.details_compact_pages {
		if page.source_page == a.details_page { a.details_compact_page = index; return }
	}
}

fn (mut a SoftwareApp) build_details_compact(width int, height int) ui2.Element {
	a.details_compact_mode = true
	a.anchor_details_compact_page()
	mut children := frame_elements(10)
	content_width := if width > 28 { width - 28 } else { 1 }
	back_width := if content_width >= 56 { 56 } else { content_width }
	children << software_button('software.details.back', 'Back', if width > back_width + 28 { width - back_width - 14 } else { 14 }, 8, back_width)
	if width < 180 || height < 220 {
		children << software_label('Enlarge to read package details.', 14, 46, content_width, 28, false)
		return ui2.screen(app_surface, children)
	}
	children << software_label(software_details_titles[a.details_section], 14, 46, content_width, 28, false)
	button_width := (width - 42) / 2
	children << software_button('software.details.section.previous', 'Prev section', 14, 80, button_width)
	children << software_button('software.details.section.next', 'Next section', width - 14 - button_width, 80, button_width)
	if a.details_compact_page >= 0 && a.details_compact_page < a.details_compact_pages.len {
		page := a.details_compact_pages[a.details_compact_page]
		children << software_label(page.label, 14, 8, width - back_width - 42, 28, false)
		software_page_lines(mut children, page.text, 14, 118, content_width, 18)
	}
	children << software_button('software.details.previous', 'Previous', 14, height - 36, button_width)
	children << software_button('software.details.next', 'Next', width - 14 - button_width, height - 36, button_width)
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) build_details(width int, height int) ui2.Element {
	if width < 640 || height < 610 { return a.build_details_compact(width, height) }
	a.details_compact_mode = false
	mut children := frame_elements(32)
	children << software_label('Package details', 14, 8, width - 202, 28, false)
	children << software_button('software.details.back', if a.details_review { 'Back to review' } else { 'Back to packages' }, width - 174, 8, 160)
	children << software_label(if a.details_review { 'Reviewed package change' } else { 'Catalog and installed package information' }, 14, 46, width - 28, 28, false)
	for section in 0 .. 6 {
		children << software_button(software_details_actions[section], software_details_titles[section], 14 + section * 100, 90, 94)
	}
	if a.details_page >= 0 && a.details_page < a.details_pages.len {
		page := a.details_pages[a.details_page]
		children << software_label(page.title, 14, 132, width - 28, 28, false)
		software_page_lines(mut children, page.text, 14, 174, width - 28, 20)
		children << software_label(page.label, 238, height - 138, width - 252, 28, false)
	}
	children << software_button('software.details.previous', 'Previous', 14, height - 138, 100)
	children << software_button('software.details.next', 'Next', 126, height - 138, 100)
	children << software_label(if a.details_review { 'Browse each package, then return to the review to confirm or cancel.' } else { 'Browse all pages for complete descriptions, provenance, permissions, licensing and diagnostics.' }, 14, height - 98, width - 28, 90, false)
	return ui2.screen(app_surface, children)
}
