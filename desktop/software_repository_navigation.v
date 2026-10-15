// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (a &SoftwareApp) repository_read_running() bool {
	if !a.repository_mode || a.worker == unsafe { nil } { return false }
	return (a.repository_worker == .list && a.worker_view)
		|| (a.repository_worker == .review && a.worker_review
			&& a.repository_operation in ['enroll', 'revoke']!)
}

fn (mut a SoftwareApp) stop_repository_read() {
	// Enrollment/revocation and their authenticated catalog refresh are writes.
	// Only a configuration listing or unaccepted trust proposal can be stopped.
	if !a.repository_read_running() { return }
	reviewing := a.repository_worker == .review
	if a.worker.is_alive() { a.worker.signal_kill(); a.worker.wait() }
	a.retire_worker()
	a.repository_worker = .none; a.worker_view = false; a.worker_review = false
	if reviewing { a.clear_repository_review() }
	a.output.clear(); a.output_truncated = false
	a.repository_focus = 0; a.select_all = false
	a.set_status(if reviewing {
		'Repository review stopped. No trust change was started. Review again to continue.'
	} else {
		'Repository list read stopped. Previous list and entered fields were retained. Reload to try again.'
	})
}

fn (a &SoftwareApp) build_repositories_compact(width int, height int) ui2.Element {
	mut children := frame_elements(8)
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil }
	children << software_label('Repositories · enlarge for details', 14, 8, width - 28, 28, false)
	button_width := if width > 202 { 174 } else { width - 28 }
	if a.repository_read_running() {
		children << software_button('software.repository.stop', if a.repository_worker == .review { 'Stop review' } else { 'Stop reading' }, 14, 46, button_width)
	} else if a.worker == unsafe { nil } {
		children << software_button(if a.repository_operation != '' { 'software.repository.cancel' } else { 'software.repository.back' },
			if a.repository_operation != '' { 'Cancel review' } else { 'Back to Software' }, 14, 46, button_width)
	} else {
		children << software_label('Wait for repository changes to finish.', 14, 46, width - 28, 28, false)
	}
	if available { children << software_button('software.failure', 'Failure details', 14, 84, button_width) }
	progress := a.progress_seen && height >= 240
	if progress { children << a.progress_bar(width, height) }
	y := if height > 230 { height - if progress { 88 } else { 98 } } else if available { 122 } else { 84 }
	children << software_label(a.status, 14, y, width - 28, if height > y + 8 { height - y - 8 } else { 1 }, false)
	return ui2.screen(app_surface, children)
}
