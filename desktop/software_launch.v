// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

const software_launch_text_limit = 4096
const software_launch_file_rows = 5
const software_launch_file_actions = ['software.launch.file.0', 'software.launch.file.1', 'software.launch.file.2',
	'software.launch.file.3', 'software.launch.file.4']

fn software_launch_kind(row SoftwareRow) string {
	return if row.installed_kind != '' { row.installed_kind } else { row.kind }
}

fn (mut a SoftwareApp) clear_launch_options() {
	a.clear_details()
	unsafe { a.launch_id.free(); a.launch_name.free(); a.launch_arguments.free(); a.launch_file.free() }
	pkgprotocol.free_command_values(mut a.launch_documents)
	a.launch_id = ''; a.launch_name = ''
	a.launch_arguments = []u8{}; a.launch_file = []u8{}
	a.launch_mode = false; a.launch_focus = 0
	a.launch_compact = false; a.launch_page = 0
	a.launch_file_selected = -1; a.launch_file_scroll = 0
	a.launch_read_file = -1
	a.launch_data_cwd = true; a.launch_files_allowed = false; a.launch_hosted_display = false
}

fn (mut a SoftwareApp) prepare_launch_details() {
	a.clear_details()
	a.details_pages = []SoftwareDetailsPage{cap: 32}
	unsafe { a.details_pages.flags |= .noslices }
	mut values := ['Installed application ID: ' + a.launch_id, 'Installed application name: ' + a.launch_name,
		'Draft only. Reading does not validate or run this command.'.clone(),
		'Arguments use quotes and backslash escapes; shell operators and variables remain literal.'.clone(),
		'Argument text: ' + if a.launch_arguments.len == 0 { '(empty)' } else { editor_bytes_text(a.launch_arguments) },
		if a.launch_data_cwd { 'Working folder: This account\'s private application data, ~/.local/share/vinix-apps/' + a.launch_id }
		else { 'Working folder: Installed application directory (read-only)'.clone() }]
	unsafe { values.flags |= .noslices }
	software_details_count(mut values, 'Allowed files: ', u64(a.launch_documents.len))
	values << if a.launch_files_allowed { 'Installed manifest declares file access. Each allowed file is readable and writable by this application.'.clone() }
		else { 'Installed manifest does not declare document-file access. Private application data remains available.'.clone() }
	if a.launch_read_file >= 0 && a.launch_read_file < a.launch_documents.len {
		software_details_count(mut values, 'Allowed file number: ', u64(a.launch_read_file + 1))
		values << 'Allowed file path: ' + a.launch_documents[a.launch_read_file]
	} else if a.launch_documents.len > 0 {
		values << 'Use Next file to inspect every allowed path. Reader navigation keeps the form\'s file selection and paging.'.clone()
	} else { values << 'No document files have been granted.'.clone() }
	values << 'Entered file path (not yet granted): ' + if a.launch_file.len == 0 { '(empty)' } else { editor_bytes_text(a.launch_file) }
	values << 'An entered file must be added or cleared before running. Allowed paths must be used explicitly in arguments when needed.'.clone()
	values << 'The ordinary-account service checks current installed state, trust, policy, file existence and access at launch.'.clone()
	values << 'Return to Launch options to edit, add or remove grants, change the working folder or run.'.clone()
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

fn (mut a SoftwareApp) open_launch_options() {
	if a.selected < 0 || a.selected >= a.rows.len { return }
	row := a.rows[a.selected]
	if row.installed_version == '' || row.installed_window_protocol != 0 || software_launch_kind(row) in ['runtime', 'data'] { return }
	a.clear_launch_options()
	a.clear_review(); a.clear_repository_review()
	a.repository_mode = false; a.deployment_mode = false; a.focus = false; a.select_all = false
	a.launch_id = row.id.clone()
	a.launch_name = if row.installed_name != '' { row.installed_name.clone() } else { row.name.clone() }
	// Update presentation describes the planned candidate. Launch presentation
	// uses the installed manifest, including an explicitly empty permission set.
	a.launch_files_allowed = if row.installed_kind != '' { 'files' in row.installed_permissions } else { 'files' in row.permissions }
	// Freeze the installed display grant with this draft. Candidate permissions
	// never choose the private X11 session used to launch installed code.
	a.launch_hosted_display = 'display' in row.installed_permissions
	a.launch_arguments = []u8{cap: software_launch_text_limit}
	a.launch_file = []u8{cap: software_launch_text_limit}
	a.launch_documents = []string{cap: 16}
	unsafe { a.launch_arguments.flags |= .noslices; a.launch_file.flags |= .noslices; a.launch_documents.flags |= .noslices }
	a.launch_mode = true
	a.set_status('Enter application options. Quote values with spaces. Files added below are readable and writable by the app.')
}

fn (mut a SoftwareApp) add_launch_file() {
	if !a.launch_files_allowed { a.set_status('This application does not declare file access.'); return }
	path := editor_bytes_text(a.launch_file)
	if !software_deployment_path_valid(path) { a.set_status('Enter an absolute file path without control characters.'); return }
	if path in a.launch_documents { a.set_status('This file is already allowed.'); return }
	if a.launch_documents.len == pkgprotocol.command_argument_limit { a.set_status('At most 256 files can be allowed.'); return }
	// Existence, ordinary-user access and policy are checked by the service at
	// launch. The root desktop does not decide access on that user's behalf.
	a.launch_documents << path.clone()
	a.launch_file.clear(); a.launch_file_selected = a.launch_documents.len - 1
	a.launch_file_scroll = if a.launch_documents.len > software_launch_file_rows { a.launch_documents.len - software_launch_file_rows } else { 0 }
	a.set_status('File added. Use its path explicitly in the application options when needed.')
}

fn (mut a SoftwareApp) launch_with_options(terminal bool) {
	mut words := pkgprotocol.command_words(editor_bytes_text(a.launch_arguments)) or { a.set_status(err.msg()); unsafe { err.free() }; return }
	defer { pkgprotocol.free_command_values(mut words) }
	if a.launch_file.len > 0 { a.set_status('Add the entered file to Allowed files, or clear its path before launching.'); return }
	if terminal {
		a.open_terminal_command(a.launch_id, words, a.launch_documents, a.launch_data_cwd) or { a.set_status(err.msg()); unsafe { err.free() }; return }
		a.clear_launch_options()
		return
	}
	mut vector := pkgprotocol.command_vector(a.launch_id, words, a.launch_documents, a.launch_data_cwd, false) or { a.set_status(err.msg()); unsafe { err.free() }; return }
	defer { pkgprotocol.free_command_values(mut vector) }
	if a.launch_hosted_display {
		a.open_hosted_package_command(vector) or { a.set_status(err.msg()); unsafe { err.free() }; return }
		a.clear_launch_options()
		return
	}
	a.start(vector, false)
	if a.worker != unsafe { nil } {
		a.worker_run = true; a.launch_focus = 0; a.select_all = false
		a.set_status('Starting application with the chosen options and file access…')
	}
}

fn (mut a SoftwareApp) handle_launch_options(event_id string) {
	if a.worker != unsafe { nil } { return }
	for row, action in software_launch_file_actions {
		if event_id == action {
			index := a.launch_file_scroll + row
			if index < a.launch_documents.len { a.launch_file_selected = index }
			return
		}
	}
	match event_id {
		'software.launch.arguments' { a.launch_focus = 1; a.launch_page = 0; a.select_all = false }
		'software.launch.file' { a.launch_focus = 2; a.launch_page = 1; a.select_all = false }
		'software.launch.page.previous' { a.navigate_launch_page(-1) }
		'software.launch.page.next' { a.navigate_launch_page(1) }
		'software.launch.file.previous' { if a.launch_file_scroll > 0 { a.launch_file_scroll-- } }
		'software.launch.file.next' { if a.launch_file_scroll + 1 < a.launch_documents.len { a.launch_file_scroll++ } }
		'software.launch.add-file' { a.add_launch_file() }
		'software.launch.remove-file' {
			if a.launch_file_selected >= 0 && a.launch_file_selected < a.launch_documents.len {
				unsafe { a.launch_documents[a.launch_file_selected].free() }
				a.launch_documents.delete(a.launch_file_selected)
				a.launch_file_selected = -1
				if a.launch_file_scroll >= a.launch_documents.len { a.launch_file_scroll = if a.launch_documents.len > software_launch_file_rows { a.launch_documents.len - software_launch_file_rows } else { 0 } }
			}
		}
		'software.launch.up' { a.launch_file_scroll = if a.launch_file_scroll > software_launch_file_rows { a.launch_file_scroll - software_launch_file_rows } else { 0 } }
		'software.launch.down' { if a.launch_file_scroll + software_launch_file_rows < a.launch_documents.len { a.launch_file_scroll += software_launch_file_rows } }
		'software.launch.data-cwd' { a.launch_data_cwd = !a.launch_data_cwd }
		'software.launch.run' { a.launch_with_options(false) }
		'software.launch.terminal' { a.launch_with_options(true) }
		'software.launch.back' {
			a.clear_launch_options(); a.select_all = false
			a.set_status('Select an application to review its publisher, license and permissions.')
		}
		else {}
	}
}

fn (mut a SoftwareApp) launch_key_input(input string) {
	if a.worker != unsafe { nil } { return }
	if input == '\x1b' {
		if a.launch_focus != 0 { a.launch_focus = 0; a.select_all = false }
		else { a.handle_launch_options('software.launch.back') }
		return
	}
	if a.launch_focus == 0 {
		if a.launch_compact {
			match input {
				'\x1b[D', '\x1b[5~' { a.navigate_launch_page(-1) }
				'\x1b[C', '\x1b[6~' { a.navigate_launch_page(1) }
				else {}
			}
		}
		return
	}
	if input == '\x01' { a.select_all = true; return }
	if input in ['\r', '\n'] { a.launch_focus = 0; a.select_all = false; return }
	if input in ['\x7f', '\x08'] {
		if a.launch_focus == 1 { console_backspace(mut a.launch_arguments, a.select_all) }
		else { console_backspace(mut a.launch_file, a.select_all) }
		a.select_all = false; return
	}
	a.launch_paste_input(input)
}

fn (mut a SoftwareApp) launch_paste_input(input string) {
	// Pasted Escape/Enter/control bytes are text to validate, never navigation.
	if a.worker != unsafe { nil } || a.launch_focus == 0 || input == '' { return }
	length := if a.select_all { 0 } else if a.launch_focus == 1 { a.launch_arguments.len } else { a.launch_file.len }
	if input.len > software_launch_text_limit - length || !software_deployment_text_valid(input) {
		a.set_status('The field was kept intact: enter valid text without control characters, at most 4096 bytes.'); return
	}
	if a.launch_focus == 1 {
		if a.select_all { a.launch_arguments.clear() }
		for byte in input { a.launch_arguments << byte }
	} else {
		if a.select_all { a.launch_file.clear() }
		for byte in input { a.launch_file << byte }
	}
	a.select_all = false
}

fn (mut a SoftwareApp) build_launch_options(width int, height int) ui2.Element {
	a.launch_compact = false
	mut children := frame_elements(28)
	busy := a.worker != unsafe { nil }
	children << software_label('Launch options · ' + a.launch_name, 14, 8, width - 202, 28, true)
	if !busy { children << software_button('software.launch.back', 'Back to catalog', width - 174, 8, 160) }
	children << software_label(a.launch_label, 14, 44, width - 28, 28, false)
	children << software_label('Arguments', 14, 78, width - 28, 24, false)
	children << console_field('software.launch.arguments', editor_bytes_text(a.launch_arguments), 14, 106, width - 28, a.launch_focus == 1 && !busy)
	children << software_label('Quotes group values; backslash escapes a character. Shell operators and variables stay literal.', 14, 140, width - 28, 38, false)
	children << software_button('software.launch.data-cwd', if a.launch_data_cwd { 'Working folder: private app data' } else { 'Working folder: installed app' }, 14, 184, 310)
	children << software_label(if a.launch_data_cwd { 'Relative output files are saved in this app\'s personal data folder.' } else { 'Installed files are read-only. Use an allowed existing file or an absolute private-data path for output.' }, 14, 216, width - 28, 38, false)
	if a.launch_files_allowed {
		children << software_label('Allowed files · add an existing file (absolute path)', 14, 258, width - 28, 24, false)
		children << console_field('software.launch.file', editor_bytes_text(a.launch_file), 14, 286, width - 150, a.launch_focus == 2 && !busy)
		if !busy { children << software_button('software.launch.add-file', 'Add file', width - 126, 286, 112) }
		for row in 0 .. software_launch_file_rows {
			index := a.launch_file_scroll + row
			if index >= a.launch_documents.len { break }
			children << ui2.button(software_launch_file_actions[row], a.launch_documents[index], ui2.rect(14, f64(322 + row * 28), f64(width - 202), 26),
				ui2.BoxStyle{ bg: if index == a.launch_file_selected { settings_choice_bg } else { body_panel }, radius: 3 }, ui2.TextStyle{ color: body_text, size: 12 })
		}
		if !busy && a.launch_file_selected >= 0 { children << software_button('software.launch.remove-file', 'Remove file', width - 174, 322, 160) }
		if !busy && a.launch_documents.len > software_launch_file_rows {
			children << software_button('software.launch.up', 'Previous files', width - 174, 354, 160)
			children << software_button('software.launch.down', 'Next files', width - 174, 386, 160)
		}
	} else { children << software_label('This application has no document-file permission. Its private data remains available.', 14, 258, width - 28, 50, false) }
	if !busy {
		children << software_button('software.launch.run', 'Run', 14, height - 138, 100)
		children << software_button('software.launch.terminal', 'Run in Terminal', 126, height - 138, 160)
		children << software_button('software.report.read', 'Read draft', 298, height - 138, 130)
	}
	a.add_status_footer(mut children, width, height, false)
	return ui2.screen(app_surface, children)
}
