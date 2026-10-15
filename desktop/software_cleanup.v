// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

enum SoftwareCleanupWorker { none review apply }

fn (mut a SoftwareApp) clear_cleanup_review() {
	a.clear_details()
	a.cleanup_snapshot.close()
	a.cleanup_ready = false
	a.cleanup_scroll = 0
	unsafe { a.cleanup_summary.free() }
	a.cleanup_summary = ''
}

fn (mut a SoftwareApp) clear_cleanup() {
	a.clear_cleanup_review()
	a.cleanup_mode = false
	unsafe { a.cleanup_result.free() }
	a.cleanup_result = ''
}

fn (mut a SoftwareApp) read_cleanup() {
	a.clear_cleanup_review()
	a.start(['cleanup-review'], true)
	if a.worker != unsafe { nil } { a.cleanup_worker = .review }
	a.set_status('Reviewing obsolete package generations…')
}

fn (mut a SoftwareApp) prepare_cleanup_details() {
	a.clear_details()
	a.details_pages = []SoftwareDetailsPage{cap: 16}
	unsafe { a.details_pages.flags |= .noslices }
	mut values := ['Architecture: ' + a.cleanup_snapshot.architecture,
		'Review fingerprint: ' + a.cleanup_snapshot.fingerprint]
	unsafe { values.flags |= .noslices }
	software_details_count(mut values, 'Current generation retained: ', a.cleanup_snapshot.generation)
	software_details_count(mut values, 'Rollback generation retained: ', a.cleanup_snapshot.previous)
	software_details_count(mut values, 'Obsolete generations to delete: ', u64(a.cleanup_snapshot.generations.len))
	values << 'Deletion is permanent for the listed versions. Current, rollback and versions held by running applications are protected.'.clone()
	values << 'Cached complete and partial downloads, interrupted stages and personal application data are retained.'.clone()
	values << 'Reload after applications finish to review newly eligible versions. Changes to the reviewed state require a fresh review before deletion.'.clone()
	if a.cleanup_snapshot.generations.len == 0 { values << 'No obsolete generations are listed for deletion.'.clone() }
	for generation in a.cleanup_snapshot.generations {
		software_details_count(mut values, 'Remove generation ', generation)
	}
	a.details_values(0, values)
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

fn (mut a SoftwareApp) load_cleanup_review() {
	a.clear_cleanup_review()
	mut review := pkgprotocol.decode_cleanup_review(editor_bytes_text(a.output)) or {
		unsafe { err.free() }
		a.set_status('Invalid or incomplete cleanup review. Reload before confirming.')
		return
	}
	a.cleanup_snapshot = review
	a.cleanup_ready = true
	current := review.generation.str()
	previous := review.previous.str()
	count := review.generations.len.str()
	a.cleanup_summary = review.architecture + ' · Current: ' + current + ' · Rollback: ' + previous + ' · Obsolete generations: ' + count
	unsafe { current.free(); previous.free(); count.free() }
	a.prepare_cleanup_details()
	a.set_status(if a.cleanup_result != '' { a.cleanup_result } else {
		'Only the listed obsolete generations will be deleted. Current, rollback and running applications stay protected. Reload after applications finish to review newly eligible generations.'
	})
	unsafe { a.cleanup_result.free() }; a.cleanup_result = ''
}

fn (mut a SoftwareApp) handle_cleanup(event_id string) {
	if a.cleanup_review_running() && event_id in ['software.cleanup.stop', 'software.cleanup.cancel']! {
		a.stop_cleanup_review()
		return
	}
	if a.worker != unsafe { nil } { return }
	match event_id {
		'software.cleanup.back' { a.clear_cleanup() }
		'software.cleanup.reload' { a.read_cleanup() }
		'software.cleanup.confirm' {
			if !a.cleanup_ready || a.cleanup_snapshot.generations.len == 0 { return }
			a.start(['cleanup-apply', a.cleanup_snapshot.fingerprint], false)
			if a.worker != unsafe { nil } { a.cleanup_worker = .apply; a.cleanup_ready = false }
		}
		'software.cleanup.up' { a.cleanup_scroll = if a.cleanup_scroll > a.page_rows { a.cleanup_scroll - a.page_rows } else { 0 } }
		'software.cleanup.down' {
			if a.cleanup_scroll + a.page_rows < a.cleanup_snapshot.generations.len { a.cleanup_scroll += a.page_rows }
		}
		else {}
	}
}

fn (mut a SoftwareApp) build_cleanup(width int, height int) ui2.Element {
	mut children := frame_elements(32)
	children << software_label('Clean up obsolete package generations', 14, 8, width - 202, 28, false)
	if a.cleanup_review_running() { children << software_button('software.cleanup.stop', 'Stop review', width - 174, 8, 160) }
	children << software_label(a.cleanup_summary, 14, 48, width - 28, 48, false)
	children << software_label('Deletion is permanent for the listed versions. The current and rollback generations and versions used by running apps are retained. Cached downloads, interrupted stages and personal data are retained.', 14, 106, width - 28, 88, false)
	rows := if height > 390 { (height - 390) / 30 } else { 1 }
	a.page_rows = if rows > 16 { 16 } else if rows < 1 { 1 } else { rows }
	for slot in 0 .. a.page_rows {
		index := a.cleanup_scroll + slot
		if index >= a.cleanup_snapshot.generations.len { break }
		number := a.cleanup_snapshot.generations[index].str()
		children << software_label('Remove generation ' + number, 14, 204 + slot * 30, width - 28, 28, true)
		unsafe { number.free() }
	}
	if a.worker == unsafe { nil } {
		children << software_button('software.cleanup.back', 'Back to catalog', 14, height - 138, 140)
		children << software_button('software.cleanup.reload', 'Reload review', 166, height - 138, 118)
		if a.cleanup_ready && a.details_pages.len > 0 {
			children << software_button('software.report.read', 'Read review', 488, height - 138, width - 502)
		}
		if a.cleanup_ready && a.cleanup_snapshot.generations.len > 0 {
			children << software_button('software.cleanup.confirm', 'Delete listed versions', 296, height - 138, 180)
		}
		if a.cleanup_snapshot.generations.len > a.page_rows {
			children << software_button('software.cleanup.up', 'Previous', 14, height - 176, 110)
			children << software_button('software.cleanup.down', 'Next', 136, height - 176, 110)
		}
	}
	if a.progress_seen { children << a.progress_bar(width, height) }
	a.add_status_footer(mut children, width, height, a.progress_seen)
	return ui2.screen(app_surface, children)
}
