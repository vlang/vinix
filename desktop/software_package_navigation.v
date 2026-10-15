// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (a &SoftwareApp) package_screen_active() bool {
	return !a.deployment_mode && !a.mirror_mode && !a.repository_mode && !a.policy_mode
		&& !a.data_mode && !a.launch_mode && !a.health_mode && !a.cleanup_mode
		&& !a.audit_mode && !a.snapshot_mode && !a.window_mode && a.terminal_app == unsafe { nil }
}

fn (a &SoftwareApp) package_review_running() bool {
	return a.package_screen_active() && a.worker != unsafe { nil } && a.worker_review
		&& a.review in ['install', 'remove', 'upgrade', 'repair', 'rollback']!
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
	mut children := frame_elements(8)
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil } && !a.details_mode
	children << software_label('Software · enlarge for package details', 14, 8, width - 28, 28, false)
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
	if available { children << software_button('software.failure', 'Failure details', 14, 84, button_width) }
	progress := a.progress_seen && height >= 240
	if progress { children << a.progress_bar(width, height) }
	y := if height > 230 { height - if progress { 88 } else { 98 } } else if available { 122 } else { 84 }
	children << software_label(a.status, 14, y, width - 28, if height > y + 8 { height - y - 8 } else { 1 }, false)
	return ui2.screen(app_surface, children)
}
