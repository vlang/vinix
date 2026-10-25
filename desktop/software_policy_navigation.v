// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (a &SoftwareApp) policy_read_running() bool {
	if !a.policy_mode || a.worker == unsafe { nil } { return false }
	return (a.policy_worker == .list && a.worker_view)
		|| (a.policy_worker == .review && a.worker_review && a.policy_pending != '')
}

fn (mut a SoftwareApp) stop_policy_read() {
	// A policy read/proposal is public and read-only; an approved save is not.
	if !a.policy_read_running() { return }
	reviewing := a.policy_worker == .review
	if a.worker.is_alive() { a.worker.signal_kill(); a.worker.wait() }
	a.retire_worker(); a.policy_worker = .none
	a.worker_view = false; a.worker_review = false
	a.clear_policy_review()
	if reviewing { a.prepare_policy_pages(false) }
	// A stopped reload can follow a successful save. Keep policy_ready false:
	// the cached document must not authorize a new review until a fresh read.
	a.output.clear(); a.output_truncated = false
	a.focus = false; a.select_all = false
	a.set_status(if reviewing {
		'Policy review stopped. No policy change was started. Review again to continue.'
	} else {
		'Policy read stopped. Reload the current policy before reviewing a change.'
	})
}

const software_policy_reader_titles = ['General', 'Allowed IDs', 'Version pins', 'Permissions', 'Licenses', 'Policy file', 'App effects']

fn (mut a SoftwareApp) anchor_policy_compact_page() {
	if a.policy_compact_page >= 0 && a.policy_compact_page < a.policy_compact_pages.len
		&& a.policy_compact_pages[a.policy_compact_page].source_page == a.policy_page { return }
	for index, page in a.policy_compact_pages {
		if page.source_page == a.policy_page { a.policy_compact_page = index; return }
	}
}

fn (mut a SoftwareApp) navigate_policy(action string) {
	if !a.policy_ready || a.policy_pages.len == 0 { return }
	if action in ['software.policy.previous', 'software.policy.next']! {
		step := if action == 'software.policy.next' { 1 } else { -1 }
		if a.policy_compact_mode {
			a.anchor_policy_compact_page()
			next := a.policy_compact_page + step
			if next >= 0 && next < a.policy_compact_pages.len {
				canonical := a.policy_compact_pages[next].source_page
				if a.policy_pages[canonical].section == a.policy_section {
					a.policy_compact_page = next; a.policy_page = canonical
				}
			}
			return
		}
		mut index := a.policy_page + step
		for index >= 0 && index < a.policy_pages.len {
			if a.policy_pages[index].section == a.policy_section { a.policy_page = index; break }
			index += step
		}
		return
	}
	if action in ['software.policy.section.previous', 'software.policy.section.next']! {
		step := if action == 'software.policy.section.next' { 1 } else { -1 }
		mut section := a.policy_section + step
		for section >= 0 && section < software_policy_sections.len {
			if a.policy_starts[section] >= 0 { a.navigate_policy(software_policy_sections[section]); break }
			section += step
		}
		return
	}
	for section, event_id in software_policy_sections {
		if action == event_id && a.policy_starts[section] >= 0 {
			a.policy_section = section; a.policy_page = a.policy_starts[section]; a.focus = false
			a.anchor_policy_compact_page(); return
		}
	}
}

fn (mut a SoftwareApp) handle_policy_reader(action string) {
	if a.worker != unsafe { nil } { return }
	if action == 'software.policy.reader.back' { a.policy_reader_mode = false; a.policy_compact_mode = false; return }
	// Only disclosure navigation can reach the underlying policy workflow.
	a.navigate_policy(action)
}

fn (mut a SoftwareApp) policy_reader_key_input(input string) {
	match input {
		'\x1b' { a.handle_policy_reader('software.policy.reader.back') }
		'\x1b[D', '\x1b[5~' { a.navigate_policy('software.policy.previous') }
		'\x1b[C', '\x1b[6~' { a.navigate_policy('software.policy.next') }
		'\x1b[A', '\x1b[Z' { a.navigate_policy('software.policy.section.previous') }
		'\x1b[B', '\t' { a.navigate_policy('software.policy.section.next') }
		else {}
	}
}

fn (mut a SoftwareApp) build_policy_reader(width int, height int) ui2.Element {
	a.policy_compact_mode = width < 640 || height < 610
	a.anchor_policy_compact_page()
	mut children := frame_elements(if a.policy_compact_mode { 10 } else { 32 })
	content_width := if width > 28 { width - 28 } else { 1 }
	if a.policy_compact_mode {
		back_width := if content_width >= 56 { 56 } else { content_width }
		children << software_button('software.policy.reader.back', 'Back', if width > back_width + 28 { width - back_width - 14 } else { 14 }, 8, back_width)
		if width < 180 || height < 220 {
			children << software_label('Enlarge to read policy.', 14, 46, content_width, 28, false)
			return ui2.screen(app_surface, children)
		}
		children << software_label(software_policy_reader_titles[a.policy_section], 14, 46, content_width, 28, false)
		button_width := (width - 42) / 2
		children << software_button('software.policy.section.previous', 'Prev topic', 14, 80, button_width)
		children << software_button('software.policy.section.next', 'Next topic', width - 14 - button_width, 80, button_width)
		if a.policy_compact_page >= 0 && a.policy_compact_page < a.policy_compact_pages.len {
			page := a.policy_compact_pages[a.policy_compact_page]
			children << software_label(page.label, 14, 8, width - back_width - 42, 28, false)
			software_page_lines(mut children, page.text, 14, 118, content_width, 18)
		}
		children << software_button('software.policy.previous', 'Previous', 14, height - 36, button_width)
		children << software_button('software.policy.next', 'Next', width - 14 - button_width, height - 36, button_width)
	} else {
		children << software_label('Organization policy details', 14, 8, width - 202, 28, false)
		children << software_button('software.policy.reader.back', 'Back to policy', width - 174, 8, 160)
		for section in 0 .. 7 {
			if a.policy_starts[section] < 0 { continue }
			children << software_button(software_policy_sections[section], software_policy_reader_titles[section], 14 + section * 86, 90, 80)
		}
		if a.policy_page >= 0 && a.policy_page < a.policy_pages.len {
			page := a.policy_pages[a.policy_page]
			children << software_label(page.title, 14, 132, content_width, 28, false)
			software_page_lines(mut children, page.text, 14, 174, content_width, 20)
			children << software_label(page.label, 238, height - 138, width - 252, 28, false)
		}
		children << software_button('software.policy.previous', 'Previous', 14, height - 138, 100)
		children << software_button('software.policy.next', 'Next', 126, height - 138, 100)
		children << software_label('Read all topics, then return to the policy screen to review, confirm or cancel a change.', 14, height - 98, content_width, 90, false)
	}
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) build_policy_compact(width int, height int) ui2.Element {
	a.policy_compact_mode = false
	mut children := frame_elements(8)
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil }
	children << software_label(if a.policy_ready { 'Organization policy' } else { 'Organization policy · enlarge for details' }, 14, 8, width - 28, 28, false)
	button_width := if width > 202 { 174 } else { width - 28 }
	if a.policy_read_running() {
		children << software_button('software.policy.stop', if a.policy_worker == .review { 'Stop review' } else { 'Stop reading' }, 14, 46, button_width)
	} else if a.worker == unsafe { nil } {
		children << software_button(if a.policy_review_ready { 'software.policy.cancel' } else { 'software.policy.back' },
			if a.policy_review_ready { 'Cancel review' } else { 'Back to deployment' }, 14, 46, button_width)
	} else {
		children << software_label('Wait for the policy save to finish.', 14, 46, width - 28, 28, false)
	}
	mut next_y := 84
	if a.worker == unsafe { nil } && a.policy_ready && height >= 220 {
		children << software_button('software.policy.read', 'Read policy', 14, next_y, button_width)
		next_y += 38
	} else if a.worker == unsafe { nil } && !a.policy_ready && !a.policy_review_ready
		&& next_y + 46 <= height {
		children << software_button('software.policy.reload', 'Reload policy', 14, next_y, button_width)
		next_y += 38
	}
	if available && next_y + 46 <= height {
		children << software_button('software.failure', 'Failure details', 14, next_y, button_width)
		next_y += 38
	}
	progress := a.progress_seen && height >= 240 && next_y <= height - 110
	if progress { children << a.progress_bar(width, height) }
	preferred_y := if height > 230 { height - if progress { 88 } else { 98 } } else { next_y }
	y := if preferred_y > next_y { preferred_y } else { next_y }
	children << software_label(a.status, 14, y, width - 28, if height > y + 8 { height - y - 8 } else { 1 }, false)
	return ui2.screen(app_surface, children)
}
