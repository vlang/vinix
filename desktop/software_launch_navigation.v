// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

fn (a &SoftwareApp) build_launch_compact(width int, height int) ui2.Element {
	mut children := frame_elements(6)
	children << software_label('Launch options · enlarge for details', 14, 8, width - 28, 28, false)
	button_width := if width > 202 { 174 } else { width - 28 }
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil }
	if a.worker == unsafe { nil } {
		children << software_button('software.launch.back', 'Back to catalog', 14, 46, button_width)
	} else {
		// The service holds runtime leases for the running application. Resizing
		// or navigating must not kill it while it can still use those files.
		children << software_label('Close the application before returning.', 14, 46, width - 28, 40, false)
	}
	if available { children << software_button('software.failure', 'Failure details', 14, 84, button_width) }
	y := if height > 230 { height - 98 } else if available { 122 } else { 92 }
	children << software_label(a.status, 14, y, width - 28, if height > y + 8 { height - y - 8 } else { 1 }, false)
	return ui2.screen(app_surface, children)
}
