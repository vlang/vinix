// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

enum SoftwareDataWorker {
	none
	list
	purge
}

fn (mut a SoftwareApp) clear_data_confirmation() {
	a.clear_details()
	unsafe { a.data_pending.free() }
	a.data_pending = ''
}

fn (mut a SoftwareApp) clear_personal_data() {
	a.clear_data_confirmation()
	a.data_status.close()
	unsafe { a.data_result.free() }
	a.data_result = ''
	a.data_ready = false
	a.data_selected = -1
	a.data_scroll = 0
}

fn (mut a SoftwareApp) read_personal_data() {
	a.clear_data_confirmation()
	a.data_ready = false
	if !a.administration_required {
		a.set_status('Sign in to an ordinary account to manage its personal application data. Root cannot select or erase another account’s data.')
		return
	}
	mut data_arguments := ['--json', 'data-list']
	a.start(data_arguments, true)
	unsafe { (&array(&data_arguments)).free() }
	if a.worker != unsafe { nil } {
		a.data_worker = .list
		a.set_status('Reading personal application data for this account…')
	}
}

fn (mut a SoftwareApp) load_personal_data() {
	a.clear_details()
	a.data_ready = false
	status := pkgprotocol.decode_personal_data(editor_bytes_text(a.output)) or {
		unsafe { err.free() }
		a.set_status('Invalid personal data response. Reload before choosing data to delete.')
		return
	}
	a.data_status.close()
	a.data_status = status
	a.data_ready = true
	a.data_selected = -1
	a.data_scroll = 0
	a.prepare_personal_data_details()
	if a.data_result != '' {
		a.set_status(a.data_result)
		unsafe { a.data_result.free() }
		a.data_result = ''
	} else {
		a.set_status(if status.rows.len == 0 { 'No personal application data was found for this account.' }
			else { 'Uninstall keeps personal data. Select an uninstalled application to review deletion of this account’s data.' })
	}
}

fn (mut a SoftwareApp) keep_data_selection_visible() {
	if a.data_selected < 0 || a.data_selected >= a.data_status.rows.len { return }
	size := if a.page_rows > 0 { a.page_rows } else { 1 }
	a.data_scroll = a.data_selected / size * size
}

fn (mut a SoftwareApp) prepare_personal_data_details() {
	a.clear_details()
	if !a.data_ready || !a.administration_required { return }
	a.details_pages = []SoftwareDetailsPage{cap: 16}
	unsafe { a.details_pages.flags |= .noslices }
	mut values := ['Only the signed-in ordinary account\'s personal application data is listed here.'.clone(),
		'Uninstall keeps personal data. Package rollback restores packages, not personal data.'.clone()]
	unsafe { values.flags |= .noslices }
	software_details_count(mut values, 'Applications with retained data: ', u64(a.data_status.rows.len))
	if a.data_pending != '' {
		values << 'Permanently delete data for: ' + a.data_pending
		values << 'Only this account\'s ~/.local/share/vinix-apps/' + a.data_pending + ' directory is deleted.'
		values << 'This cannot be undone. Documents granted to the application stay in their original locations.'.clone()
		values << 'Stop applications using retained generations before confirming. Deletion rechecks installed state, live leases and filesystem safety.'.clone()
		values << 'Reading does not approve deletion. Return to the full confirmation to cancel or delete permanently.'.clone()
	} else if a.data_selected >= 0 && a.data_selected < a.data_status.rows.len {
		row := a.data_status.rows[a.data_selected]
		values << 'Application: ' + row.id
		values << 'Location: ~/.local/share/vinix-apps/' + row.id
		values << if row.installed { 'Application is installed. Uninstall it before reviewing personal data deletion.'.clone() }
			else { 'Application is uninstalled; personal data remains.'.clone() }
		if row.diagnostic != '' { values << 'Diagnostic: ' + row.diagnostic }
		else { values << 'No inventory diagnostic was reported. Deletion still rechecks installed state, live leases and filesystem safety.'.clone() }
		values << 'This inventory is an observation, not permission to delete. Return to the full inventory to review deletion.'.clone()
	} else {
		values << if a.data_status.rows.len == 0 { 'No personal application data was found for this account.'.clone() }
			else { 'Use Next item to inspect retained application IDs, installed state and diagnostics.'.clone() }
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

fn (mut a SoftwareApp) handle_personal_data(event_id string) {
	// Confirmation is modal. Selection, reload, catalog actions and external
	// launch requests cannot change the ID that the user is being asked to erase.
	if a.data_pending != '' {
		if event_id == 'software.data.cancel' {
			a.clear_data_confirmation()
			a.prepare_personal_data_details()
			a.set_status('Personal data deletion cancelled before making changes.')
		} else if event_id == 'software.data.confirm' && a.administration_required {
			mut data_arguments := ['purge-data', a.data_pending]
			a.start(data_arguments, false)
			unsafe { (&array(&data_arguments)).free() }
			if a.worker != unsafe { nil } {
				a.data_worker = .purge
				a.set_status('Checking installed state and running apps, then deleting the confirmed personal data…')
			}
		}
		return
	}
	match event_id {
		'software.data.back' {
			a.clear_personal_data()
			a.data_mode = false
			mut data_arguments := ['view']
			a.start(data_arguments, true)
			unsafe { (&array(&data_arguments)).free() }
		}
		'software.data.reload' { a.read_personal_data() }
		'software.data.up' { a.data_scroll = if a.data_scroll > a.page_rows { a.data_scroll - a.page_rows } else { 0 } }
		'software.data.down' {
			if a.data_scroll + a.page_rows < a.data_status.rows.len { a.data_scroll += a.page_rows }
		}
		'software.data.delete' {
			if !a.administration_required || !a.data_ready || a.data_selected < 0 || a.data_selected >= a.data_status.rows.len { return }
			row := a.data_status.rows[a.data_selected]
			if row.installed { a.set_status('Uninstall the application before deleting its personal data.'); return }
			if row.diagnostic != '' { a.set_status(row.diagnostic); return }
			a.data_pending = row.id.clone()
			a.prepare_personal_data_details()
			a.set_status('Deleting personal data is permanent. Package rollback cannot restore it. Stop applications using retained generations before confirming.')
		}
		else {
			if !a.data_ready { return }
			for slot, action in software_row_actions {
				if event_id == action && a.data_scroll + slot < a.data_status.rows.len {
					a.data_selected = a.data_scroll + slot
					a.prepare_personal_data_details()
					return
				}
			}
		}
	}
}

fn (mut a SoftwareApp) build_personal_data(width int, height int) ui2.Element {
	mut children := frame_elements(32)
	children << software_label('Personal application data', 14, 8, width - 28, 28, false)
	if a.worker != unsafe { nil } {
		if a.data_read_running() {
			children << software_button('software.data.stop', 'Stop reading', 14, 46, 140)
		} else {
			children << software_label('Wait for the confirmed deletion to finish.', 14, 46, width - 28, 28, false)
		}
	} else if a.data_pending != '' {
		children << software_label('Permanently delete data for:', 14, 56, width - 28, 28, false)
		children << software_label(a.data_pending, 14, 92, width - 28, 48, false)
		children << software_label('Only this signed-in account’s ~/.local/share/vinix-apps/ID directory is deleted. Documents granted to the application stay in their original locations.', 14, 152, width - 28, 76, false)
		children << software_label('This cannot be undone. Package rollback restores packages, but does not restore personal data.', 14, 244, width - 28, 60, false)
		children << software_button('software.data.confirm', 'Delete permanently', 14, height - 138, 164)
		children << software_button('software.data.cancel', 'Cancel', 190, height - 138, 100)
		if a.details_pages.len > 0 { children << software_button('software.report.read', 'Read review', 302, height - 138, 140) }
	} else {
		children << software_button('software.data.back', 'Back to catalog', 14, 46, 140)
		if a.administration_required {
			children << software_button('software.data.reload', 'Reload', 166, 46, 96)
			if a.data_ready && a.details_pages.len > 0 { children << software_button('software.report.read', 'Read inventory', 274, 46, 150) }
			if a.data_ready {
				for slot in 0 .. a.page_rows {
					index := a.data_scroll + slot
					if index >= a.data_status.rows.len { break }
					row := a.data_status.rows[index]
					children << ui2.button(software_row_actions[slot], row.id,
						ui2.rect(14, f64(90 + slot * 30), 236, 28),
						ui2.BoxStyle{ bg: if index == a.data_selected { settings_choice_bg } else { body_panel }, radius: 3 },
						ui2.TextStyle{ color: body_text, size: 12, align: .left })
				}
				children << software_button('software.data.up', 'Previous', 14, height - 138, 110)
				children << software_button('software.data.down', 'Next', 136, height - 138, 110)
				if a.data_selected >= 0 && a.data_selected < a.data_status.rows.len {
					row := a.data_status.rows[a.data_selected]
					children << software_label(row.id, 274, 90, width - 288, 48, false)
					children << software_label(if row.installed { 'Application is installed. Uninstall it first.' } else { 'Application is uninstalled; personal data remains.' }, 274, 152, width - 288, 72, false)
					children << software_label('Location: ~/.local/share/vinix-apps/ID\nOnly the current account’s data is managed here.', 274, 236, width - 288, 72, false)
					if row.diagnostic != '' {
						children << software_label(row.diagnostic, 274, 324, width - 288, 90, false)
					} else if !row.installed {
						children << software_button('software.data.delete', 'Review deletion', 274, height - 138, 150)
					}
				}
			}
		}
	}
	if a.progress_seen { children << a.progress_bar(width, height) }
	a.add_status_footer(mut children, width, height, a.progress_seen)
	return ui2.screen(app_surface, children)
}
