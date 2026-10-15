// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (a &SoftwareApp) data_read_running() bool {
	return a.data_mode && a.worker != unsafe { nil } && a.data_worker == .list && a.worker_view
}

fn (mut a SoftwareApp) stop_data_read() {
	// Inventory reads are observations. Never interrupt a confirmed deletion.
	if !a.data_read_running() { return }
	if a.worker.is_alive() { a.worker.signal_kill(); a.worker.wait() }
	a.retire_worker(); a.data_worker = .none
	a.worker_view = false; a.worker_review = false
	a.clear_data_confirmation()
	// The retained inventory may predate a completed purge. Only a fresh,
	// successful read can make its rows available for another confirmation.
	a.data_ready = false
	a.output.clear(); a.output_truncated = false
	a.set_status('Personal data inventory read stopped. Reload before choosing data to delete.')
}

fn (mut a SoftwareApp) data_key_input(input string) {
	if input != '\x1b' { return }
	if a.data_read_running() { a.stop_data_read(); return }
	if a.worker != unsafe { nil } { return }
	a.handle_personal_data(if a.data_pending != '' { 'software.data.cancel' } else { 'software.data.back' })
}

fn (a &SoftwareApp) build_personal_data_compact(width int, height int) ui2.Element {
	mut children := frame_elements(10)
	children << software_label('Personal data · enlarge for details', 14, 8, width - 28, 28, false)
	button_width := if width > 202 { 174 } else { width - 28 }
	mut next_y := 84
	if a.data_read_running() {
		children << software_button('software.data.stop', 'Stop reading', 14, 46, button_width)
	} else if a.worker == unsafe { nil } {
		confirming := a.data_pending != ''
		children << software_button(if confirming { 'software.data.cancel' } else { 'software.data.back' },
			if confirming { 'Cancel deletion' } else { 'Back to catalog' }, 14, 46, button_width)
		if !confirming && a.administration_required {
			children << software_button('software.data.reload', 'Reload inventory', 14, next_y, button_width)
			next_y += 38
		}
	} else {
		children << software_label('Wait for deletion to finish.', 14, 46, width - 28, 28, false)
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
