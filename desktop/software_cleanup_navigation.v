// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (a &SoftwareApp) cleanup_review_running() bool {
	return a.cleanup_mode && a.worker != unsafe { nil } && a.cleanup_worker == .review && a.worker_view
}

fn (mut a SoftwareApp) stop_cleanup_review() {
	// Only an unaccepted read-only proposal may be stopped. Approved removal
	// keeps the writer and its close guard until the service exits.
	if !a.cleanup_review_running() { return }
	if a.worker.is_alive() { a.worker.signal_kill(); a.worker.wait() }
	a.retire_worker(); a.cleanup_worker = .none
	a.worker_view = false; a.worker_review = false
	a.clear_cleanup_review()
	a.output.clear(); a.output_truncated = false
	// Keep any completed cleanup result until a fresh review is admitted.
	a.set_status('Cleanup review stopped. Reload and review the complete list before confirming deletion.')
}

fn (mut a SoftwareApp) cleanup_key_input(input string) {
	if input != '\x1b' { return }
	if a.cleanup_review_running() { a.stop_cleanup_review(); return }
	if a.worker == unsafe { nil } { a.handle_cleanup('software.cleanup.back') }
}

fn (a &SoftwareApp) build_cleanup_compact(width int, height int) ui2.Element {
	mut children := frame_elements(10)
	children << software_label(if a.cleanup_ready { 'Cleanup review' } else { 'Clean up versions · enlarge for details' }, 14, 8, width - 28, 28, false)
	button_width := if width > 202 { 174 } else { width - 28 }
	mut next_y := 84
	if a.cleanup_review_running() {
		children << software_button('software.cleanup.stop', 'Stop review', 14, 46, button_width)
	} else if a.worker == unsafe { nil } {
		children << software_button('software.cleanup.back', 'Back to catalog', 14, 46, button_width)
		if a.cleanup_ready && a.details_pages.len > 0 && height >= 220 {
			children << software_button('software.report.read', 'Read review', 14, next_y, button_width)
			next_y += 38
		}
		children << software_button('software.cleanup.reload', 'Reload review', 14, next_y, button_width)
		next_y += 38
	} else {
		children << software_label('Wait for the approved cleanup to finish.', 14, 46, width - 28, 40, false)
	}
	if a.failure_pages.len > 0 && a.worker == unsafe { nil } {
		children << software_button('software.failure', 'Failure details', 14, next_y, button_width)
		next_y += 38
	}
	progress := a.progress_seen && height >= 240 && next_y <= height - 110
	if progress { children << a.progress_bar(width, height) }
	y := if height - 98 > next_y { height - if progress { 88 } else { 98 } } else { next_y }
	children << software_label(a.status, 14, y, width - 28, if height > y + 8 { height - y - 8 } else { 1 }, false)
	return ui2.screen(app_surface, children)
}
