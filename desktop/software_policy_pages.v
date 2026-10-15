// SPDX-License-Identifier: GPL-2.0-or-later
module main

import tools.packages.pkgprotocol

fn software_policy_free_lines(mut values []string) {
	unsafe { for value in values { value.free() }; (&array(&values)).free() }
	values = []string{}
}

fn (mut a SoftwareApp) add_policy_page(section int, title string, lines []string) {
	if a.policy_starts[section] < 0 { a.policy_starts[section] = a.policy_pages.len }
	page := SoftwarePolicyPage{ section: section, title: title.clone(), text: lines.join('\n') }
	pointer := unsafe { &page }
	unsafe { a.policy_pages.push_many(pointer, 1) }
}

// Every value is shown intact across UTF-8 boundaries. Group at most fourteen
// 48-byte lines per page so long IDs, ranges, filenames and diagnostics remain
// readable in the full Software layout, without formatting on redraw.
fn (mut a SoftwareApp) policy_values(section int, title string, values []string) {
	mut lines := []string{cap: 14}
	unsafe { lines.flags |= .noslices }
	defer { software_policy_free_lines(mut lines) }
	for value in values {
		if value == '' { continue }
		mut start := 0
		for start < value.len {
			mut end := if start + 48 < value.len { start + 48 } else { value.len }
			for end > start && end < value.len && value[end] & 0xc0 == 0x80 { end-- }
			chunk := unsafe { tos(value.str + start, end - start) }
			lines << (if start == 0 { '• ' } else { '  ' }) + chunk
			start = end
			if lines.len == 14 {
				a.add_policy_page(section, title, lines)
				for line in lines { unsafe { line.free() } }
				lines.clear()
			}
		}
	}
	if lines.len > 0 { a.add_policy_page(section, title, lines) }
}

fn (mut a SoftwareApp) policy_empty_page(section int, title string, text string) {
	mut values := []string{cap: 1}
	// A typed string push clones its argument. This transient input borrows it;
	// policy_values owns the resulting page text before the input is released.
	pointer := unsafe { &text }
	unsafe { values.push_many(pointer, 1) }
	a.policy_values(section, title, values)
	unsafe { (&array(&values)).free() }
}

fn (mut a SoftwareApp) policy_settings_pages(label string, architecture string, settings pkgprotocol.PolicySettings) {
	mut general := []string{cap: 5}
	reserve := settings.reserve_bytes.str()
	general << 'Architecture: ' + architecture
	general << 'Offline repositories/cache: ' + if settings.offline { 'Required' } else { 'Online acquisition permitted' }
	general << 'Firmware payload installation: ' + if settings.allow_firmware { 'Explicitly allowed' } else { 'Blocked' }
	general << 'Disk reserve: ' + reserve + ' bytes'
	general << 'Firmware permission does not flash hardware.'.clone()
	title := label + ' · General'
	a.policy_values(0, title, general)
	unsafe { reserve.free(); title.free() }; software_policy_free_lines(mut general)
	allowed_title := label + ' · Allowed package IDs (includes dependencies)'
	if settings.allowed.len == 0 { a.policy_empty_page(1, allowed_title, 'Unrestricted among packages from trusted publishers.') }
	else { a.policy_values(1, allowed_title, settings.allowed) }
	unsafe { allowed_title.free() }
	pins_title := label + ' · Version pins'
	if settings.pins.len == 0 { a.policy_empty_page(2, pins_title, 'No version pins.') }
	else {
		mut pins := []string{cap: settings.pins.len}
		for pin in settings.pins {
			lower := if pin.minimum == '' { 'any minimum' } else { pin.minimum }
			upper := if pin.before == '' { 'no upper bound' } else { pin.before }
			pins << pin.id + ': minimum ' + lower + ' (inclusive), before ' + upper + ' (exclusive)'
		}
		a.policy_values(2, pins_title, pins)
		software_policy_free_lines(mut pins)
	}
	unsafe { pins_title.free() }
	permissions_title := label + ' · Permitted application permissions'
	if settings.permissions.len == 0 { a.policy_empty_page(3, permissions_title, 'No permissions permitted.') }
	else { a.policy_values(3, permissions_title, settings.permissions) }
	unsafe { permissions_title.free() }
	licenses_title := label + ' · Explicitly accepted proprietary licenses'
	if settings.licenses.len == 0 { a.policy_empty_page(4, licenses_title, 'No proprietary licenses accepted.') }
	else { a.policy_values(4, licenses_title, settings.licenses) }
	unsafe { licenses_title.free() }
}

fn (mut a SoftwareApp) policy_impact_pages(row pkgprotocol.PolicyImpact) {
	mut values := []string{cap: 12}
	values << 'ID: ' + row.id
	values << 'Name: ' + row.name
	values << 'Version: ' + row.version + ' · Kind: ' + row.kind
	values << 'License: ' + row.license
	values << 'Proprietary: ' + if row.proprietary { 'Yes' } else { 'No' }
	values << 'Firmware: ' + if row.firmware { 'Yes' } else { 'No' }
	values << 'Installed as: ' + if row.requested { 'Requested application' } else { 'Dependency/runtime' }
	values << 'Publisher repository: ' + row.repository
	values << 'Publisher key: ' + row.public_key
	values << 'Previous policy: ' + if row.diagnostic_before == '' { 'Complete dependency closure allowed.' } else { row.diagnostic_before }
	values << 'Proposed policy: ' + if row.diagnostic_after == '' { 'Complete dependency closure allowed.' } else { row.diagnostic_after }
	title := 'Installed-app effects · ' + row.id
	a.policy_values(6, title, values)
	software_policy_free_lines(mut values)
	unsafe { title.free() }
}

fn (mut a SoftwareApp) prepare_policy_pages(reviewing bool) {
	a.clear_policy_pages()
	if !a.policy_ready { return }
	a.policy_pages = []SoftwarePolicyPage{cap: 32}
	unsafe { a.policy_pages.flags |= .noslices }
	if reviewing {
		a.policy_settings_pages('Previous policy', a.policy_snapshot.architecture, a.policy_snapshot.previous)
		a.policy_settings_pages('Proposed policy', a.policy_snapshot.architecture, a.policy_snapshot.proposed)
		a.policy_empty_page(5, 'Policy file supplied for review', a.policy_pending)
		for row in a.policy_snapshot.rows { a.policy_impact_pages(row) }
		if a.policy_snapshot.rows.len == 0 { a.policy_empty_page(6, 'Installed-app effects', 'No installed packages. This change still applies to future launches and maintenance.') }
	} else { a.policy_settings_pages('Current policy', a.policy_document.architecture, a.policy_document.policy) }
	mut counts := [7]int{}
	mut numbers := [7]int{}
	mut totals := [7]string{}
	for page in a.policy_pages { counts[page.section]++ }
	for section in 0 .. 7 { totals[section] = counts[section].str() }
	for index in 0 .. a.policy_pages.len {
		section := a.policy_pages[index].section
		numbers[section]++
		number := numbers[section].str()
		a.policy_pages[index].label = number + ' of ' + totals[section]
		unsafe { number.free() }
	}
	unsafe { for total in totals { total.free() } }
	a.policy_compact_pages = []SoftwareFailurePage{cap: 32}
	unsafe { a.policy_compact_pages.flags |= .noslices }
	// Group the short pages by topic: previous/proposed settings are interleaved
	// in the canonical document, and both must remain reachable within a topic.
	for section in 0 .. 7 {
		for index, page in a.policy_pages {
			if page.section == section {
				text := page.title + '\n' + page.text
				software_failure_paginate(mut a.policy_compact_pages, text, 12, 3, index)
				unsafe { text.free() }
			}
		}
	}
	software_failure_labels(mut a.policy_compact_pages)
}
