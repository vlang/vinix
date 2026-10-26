// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2

const software_launch_pages = ['Arguments', 'Add file', 'Files', 'Folder', 'Run', 'Failure']

fn (mut a SoftwareApp) navigate_launch_page(step int) {
	if a.worker != unsafe { nil } { return }
	last := if a.failure_pages.len > 0 { 5 } else { 4 }
	current := if a.launch_page < 0 { 0 } else if a.launch_page > last { last } else { a.launch_page }
	next := current + step
	if next < 0 || next > last { return }
	a.launch_page = next
	// Explicit navigation ends editing. A resize alone preserves field focus.
	a.launch_focus = 0; a.select_all = false
}

fn (mut a SoftwareApp) build_launch_compact(width int, height int) ui2.Element {
	a.launch_compact = true
	mut children := frame_elements(12)
	content := if width > 28 { width - 28 } else { 1 }
	busy := a.worker != unsafe { nil }
	if busy {
		// The service holds runtime leases for the running application.
		children << software_label('Launch options', 14, 8, content, 28, false)
		children << software_label('Close the application before returning.', 14, 46, content, 40, false)
		children << software_label(a.status, 14, 92, content, if height > 100 { height - 100 } else { 1 }, false)
		return ui2.screen(app_surface, children)
	}
	children << software_button('software.launch.back', 'Back', width - 70, 8, 56)
	if width < 180 || height < 220 {
		children << software_label('Launch draft is kept.', 14, 46, content, 28, false)
		if height >= 120 { children << software_button('software.status', 'Status', 14, 84, content) }
		return ui2.screen(app_surface, children)
	}
	last := if a.failure_pages.len > 0 { 5 } else { 4 }
	page := if a.launch_page < 0 { 0 } else if a.launch_page > last { last } else { a.launch_page }
	children << software_label(software_launch_pages[page], 14, 8, width - 98, 28, false)
	match page {
		0 {
			children << console_field('software.launch.arguments', editor_bytes_text(a.launch_arguments), 14, 46, content, a.launch_focus == 1)
			children << software_label('Quotes group values; shell operators and variables stay literal.', 14, 84, content, height - 128, false)
		}
		1 {
			if a.launch_files_allowed {
				children << console_field('software.launch.file', editor_bytes_text(a.launch_file), 14, 46, content, a.launch_focus == 2)
				children << software_button('software.launch.add-file', 'Add file', 14, 84, content)
				children << software_label('Absolute path. Added files are readable and writable by this app.', 14, 122, content, height - 166, false)
			} else {
				children << software_label('This app does not declare document-file access. Private app data remains available.', 14, 46, content, height - 90, false)
			}
		}
		2 {
			if a.launch_file_scroll < a.launch_documents.len {
				index := a.launch_file_scroll
				children << software_button('software.launch.file.0', a.launch_documents[index], 14, 46, content)
				button := (content - 8) / 2
				children << software_button('software.launch.file.previous', 'Prev file', 14, 84, button)
				children << software_button('software.launch.file.next', 'Next file', 22 + button, 84, button)
				if a.launch_file_selected == index {
					children << software_button('software.launch.remove-file', 'Remove file', 14, 122, content)
				} else {
					children << software_label('Select this file to remove it. Read draft shows each complete path.', 14, 122, content, height - 166, false)
				}
			} else {
				children << software_label('No document files have been granted. Use Add file to grant a path.', 14, 46, content, height - 90, false)
			}
		}
		3 {
			children << software_button('software.launch.data-cwd', if a.launch_data_cwd { 'Private app data' } else { 'Installed app' }, 14, 46, content)
			children << software_label(if a.launch_data_cwd { 'Relative output files are saved in this app\'s personal data folder.' } else { 'Installed files are read-only. Save output to an allowed file or private app data.' }, 14, 84, content, height - 128, false)
		}
		4 {
			children << software_button('software.launch.run', 'Run', 14, 46, content)
			children << software_button('software.launch.terminal', 'Run in Terminal', 14, 84, content)
			children << software_button('software.report.read', 'Read draft', 14, 122, content)
		}
		5 {
			children << software_button('software.failure', 'Failure details', 14, 46, content)
			children << software_label('Read the complete failure, then return to correct the draft and retry.', 14, 84, content, height - 128, false)
		}
		else {}
	}
	button := (content - 16) / 3
	children << software_button('software.launch.page.previous', 'Prev', 14, height - 36, button)
	children << software_button('software.status', 'Status', 22 + button, height - 36, button)
	children << software_button('software.launch.page.next', 'Next', width - 14 - button, height - 36, button)
	return ui2.screen(app_surface, children)
}
