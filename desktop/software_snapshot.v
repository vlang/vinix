// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import tools.packages.pkgprotocol

fn (a &SoftwareApp) response_limit() int {
	return if a.worker_snapshot { 32 * 1024 } else { software_output_limit }
}

fn (mut a SoftwareApp) clear_deployment_snapshot() {
	a.clear_details()
	a.snapshot_saved.close()
	unsafe { a.snapshot_pending.free() }
	a.snapshot_pending = ''
	a.snapshot_mode = false; a.snapshot_ready = false
	a.focus = false; a.select_all = false
}

fn (mut a SoftwareApp) begin_deployment_snapshot() {
	a.clear_deployment_snapshot()
	a.initialize_deployment_field()
	a.deployment_path.clear()
	a.snapshot_mode = true; a.focus = true
	a.set_status('Choose a new filename for the installed deployment. Existing files are preserved.')
}

fn (mut a SoftwareApp) save_deployment_snapshot() {
	path := editor_bytes_text(a.deployment_path)
	if !software_deployment_path_valid(path) {
		a.set_status('Enter a new absolute deployment file path without control characters (at most 4096 bytes).')
		return
	}
	unsafe { a.snapshot_pending.free() }
	a.snapshot_pending = path.clone()
	a.focus = false; a.select_all = false
	mut args := ['--json', 'deployment-snapshot-save', a.snapshot_pending]
	a.start(args, true)
	unsafe { (&array(&args)).free() }
	if a.worker != unsafe { nil } {
		// This command writes as the desktop user. Its JSON is buffered like a
		// read, but closing/canceling must not kill a possibly publishing writer.
		a.worker_snapshot = true
		a.set_status('Saving the complete installed deployment to a new file…')
	}
}

fn (mut a SoftwareApp) prepare_deployment_snapshot_details() {
	a.clear_details()
	a.details_pages = []SoftwareDetailsPage{cap: 16}
	unsafe { a.details_pages.flags |= .noslices }
	mut values := ['Saved file: ' + a.snapshot_saved.destination,
		'Saved bytes SHA-256: ' + a.snapshot_saved.sha256,
		'Architecture: ' + a.snapshot_saved.architecture]
	unsafe { values.flags |= .noslices }
	software_details_count(mut values, 'Installed generation: ', a.snapshot_saved.generation)
	software_details_count(mut values, 'Requested applications: ', a.snapshot_saved.roots)
	software_details_count(mut values, 'Packages including runtimes: ', a.snapshot_saved.packages)
	values << 'Installed metadata only. Payloads, personal data and repository trust are not backed up. Restoring requires a fresh deployment review.'.clone()
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

fn (mut a SoftwareApp) load_deployment_snapshot() bool {
	mut saved := pkgprotocol.decode_deployment_saved(editor_bytes_text(a.output)) or {
		unsafe { err.free() }
		a.set_status('Saving returned an invalid or incomplete receipt. The file may exist; inspect the destination before trying a new filename.')
		return false
	}
	if saved.destination != a.snapshot_pending {
		saved.close()
		a.set_status('The save receipt names a different destination. The file may exist; inspect the chosen destination before continuing.')
		return false
	}
	a.snapshot_saved = saved
	a.snapshot_ready = true
	a.prepare_deployment_snapshot_details()
	a.set_status('Installed deployment saved. Check installed compares metadata; Review deployment prepares changes for your approval.')
	return true
}

fn (mut a SoftwareApp) finish_deployment_snapshot(code int) {
	if code == 0 && !a.worker_failed {
		if a.load_deployment_snapshot() { return }
		a.worker_failed = true
		a.output.clear()
		for byte in a.status { a.output << byte }
	} else if a.worker_failed {
		a.set_status('The save response exceeded its size limit. The file may exist; inspect the destination before trying a new filename.')
		a.output.clear()
		for byte in a.status { a.output << byte }
	} else {
		// Preserve post-publication diagnostics ("saved, but …"). Never retry
		// automatically: an unsuccessful command can already have created a file.
		diagnostic := software_output_tail(a.output)
		a.set_status(if diagnostic.len > 0 { diagnostic } else { 'Saving failed without a receipt. Inspect the destination; the file may exist.' })
		unsafe { diagnostic.free() }
	}
	a.capture_failure(a.worker.args, code)
}

fn (mut a SoftwareApp) handle_deployment_snapshot(event_id string) {
	if a.worker != unsafe { nil } { return }
	match event_id {
		'software.snapshot.back' { a.clear_deployment_snapshot() }
		'software.snapshot.another' { a.begin_deployment_snapshot() }
		'software.snapshot.export' { a.export_deployment_snapshot() }
		'software.deployment.path' { if !a.snapshot_ready { a.focus = true; a.select_all = false } }
		'software.snapshot.save' { if !a.snapshot_ready { a.save_deployment_snapshot() } }
		'software.snapshot.previous' { if a.details_page > 0 { a.details_page-- } }
		'software.snapshot.next' { if a.details_page + 1 < a.details_pages.len { a.details_page++ } }
		'software.snapshot.audit', 'software.snapshot.review' {
			if !a.snapshot_ready { return }
			// Restore the captured literal filename, not the mutable form value.
			a.deployment_path.clear()
			for byte in a.snapshot_pending { a.deployment_path << byte }
			a.clear_deployment_snapshot()
			if event_id == 'software.snapshot.audit' { a.begin_deployment_audit() }
			else { a.begin_deployment_review() }
		}
		else {}
	}
}

fn (mut a SoftwareApp) snapshot_key_input(input string) {
	if a.worker != unsafe { nil } { return }
	if input == '\x1b' {
		if !a.snapshot_ready && a.focus {
			a.focus = false; a.select_all = false
		} else { a.handle_deployment_snapshot('software.snapshot.back') }
		return
	}
	if !a.snapshot_ready { a.deployment_key_input(input) }
}

fn (mut a SoftwareApp) snapshot_paste_input(input string) {
	if a.worker != unsafe { nil } || a.snapshot_ready || !a.focus { return }
	// Pasted controls are filename data, never navigation or editing commands.
	// Refuse the entire paste so filtering cannot silently choose another file.
	if !software_deployment_text_valid(input) {
		a.set_status('The deployment file path contains control characters or invalid UTF-8. The field was kept intact.')
		return
	}
	a.deployment_paste_input(input)
}

fn (a &SoftwareApp) build_snapshot_compact(width int, height int) ui2.Element {
	mut children := frame_elements(6)
	children << software_label(if a.snapshot_ready { 'Installed deployment saved' } else { 'Save installed · enlarge for details' }, 14, 8, width - 28, 28, false)
	button_width := if width > 202 { 174 } else { width - 28 }
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil }
	if a.worker == unsafe { nil } {
		children << software_button('software.snapshot.back', 'Back to deployment', 14, 46, button_width)
	} else {
		children << software_label('Wait for saving to finish.', 14, 46, width - 28, 28, false)
	}
	mut next_y := 84
	if a.worker == unsafe { nil } && a.snapshot_ready && height >= 220 {
		children << software_button('software.report.read', 'Read receipt', 14, next_y, button_width)
		next_y += 38
	}
	if available { children << software_button('software.failure', 'Failure details', 14, next_y, button_width); next_y += 38 }
	preferred_y := if height > 230 { height - 98 } else { next_y }
	y := if preferred_y > next_y { preferred_y } else { next_y }
	children << software_label(a.status, 14, y, width - 28, if height > y + 8 { height - y - 8 } else { 1 }, false)
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) build_deployment_snapshot(width int, height int) ui2.Element {
	if width < 640 || height < 610 { return a.build_snapshot_compact(width, height) }
	mut children := frame_elements(28)
	children << software_label('Save installed deployment', 14, 8, width - 28, 28, false)
	if a.worker == unsafe { nil } {
		children << software_button('software.snapshot.back', 'Back to deployment', 14, 46, if width > 202 { 188 } else { width - 28 })
	}
	if a.snapshot_ready {
		if a.details_page >= 0 && a.details_page < a.details_pages.len {
			software_page_lines(mut children, a.details_pages[a.details_page].text, 14, 94, width - 28, 20)
			children << software_label(a.details_pages[a.details_page].label, 14, height - 206, width - 28, 28, false)
		}
		children << software_button('software.snapshot.previous', 'Previous detail', 14, height - 168, 160)
		children << software_button('software.snapshot.next', 'Next detail', 190, height - 168, 160)
		children << software_button('software.snapshot.another', 'Save another…', 366, height - 168, 160)
		children << software_button('software.snapshot.audit', 'Check installed', 14, height - 130, 180)
		children << software_button('software.snapshot.review', 'Review deployment', 210, height - 130, 180)
		if a.snapshot_saved.packages > 0 {
			children << software_button('software.snapshot.export', 'Export offline…', 406, height - 130, 180)
		}
	} else {
		children << software_label('New deployment file (absolute path)', 14, 94, width - 28, 28, false)
		children << console_field('software.deployment.path', editor_bytes_text(a.deployment_path), 14, 128, width - 28, a.focus)
		children << software_label('Save all installed applications and their exact recorded dependencies, runtimes and requested roots. Choose a new filename in a directory you can write. Existing files will never be replaced.', 14, 174, width - 28, 60, false)
		children << software_label('This saves metadata, not application payloads or personal data. Restoring needs trusted repositories or offline media, explicit license consent and a fresh review.', 14, 246, width - 28, 60, false)
		if a.worker == unsafe { nil } { children << software_button('software.snapshot.save', 'Save installed', 14, 326, 180) }
	}
	a.add_status_footer(mut children, width, height, false)
	return ui2.screen(app_surface, children)
}
