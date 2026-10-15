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

fn (a &SoftwareApp) build_policy_compact(width int, height int) ui2.Element {
	mut children := frame_elements(8)
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil }
	children << software_label('Organization policy · enlarge for details', 14, 8, width - 28, 28, false)
	button_width := if width > 202 { 174 } else { width - 28 }
	if a.policy_read_running() {
		children << software_button('software.policy.stop', if a.policy_worker == .review { 'Stop review' } else { 'Stop reading' }, 14, 46, button_width)
	} else if a.worker == unsafe { nil } {
		children << software_button(if a.policy_review_ready { 'software.policy.cancel' } else { 'software.policy.back' },
			if a.policy_review_ready { 'Cancel review' } else { 'Back to deployment' }, 14, 46, button_width)
	} else {
		children << software_label('Wait for the policy save to finish.', 14, 46, width - 28, 28, false)
	}
	if available { children << software_button('software.failure', 'Failure details', 14, 84, button_width) }
	progress := a.progress_seen && height >= 240
	if progress { children << a.progress_bar(width, height) }
	y := if height > 230 { height - if progress { 88 } else { 98 } } else if available { 122 } else { 84 }
	children << software_label(a.status, 14, y, width - 28, if height > y + 8 { height - y - 8 } else { 1 }, false)
	return ui2.screen(app_surface, children)
}
