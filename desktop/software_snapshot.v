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
	a.snapshot_media_saved.close()
	unsafe { a.snapshot_pending.free(); a.snapshot_media_source.free(); a.snapshot_pending_sha256.free() }
	a.snapshot_pending = ''
	a.snapshot_pending_sha256 = ''
	a.snapshot_media_source = ''
	a.clear_media_receipt()
	a.snapshot_media = false
	a.snapshot_mode = false; a.snapshot_ready = false
	a.focus = false; a.select_all = false
}

fn (mut a SoftwareApp) clear_media_receipt() {
	a.snapshot_receipt = false
	a.snapshot_receipt_path.clear()
	a.snapshot_media_sha256.clear()
	a.snapshot_sha256_focus = false
}

fn (mut a SoftwareApp) begin_deployment_snapshot() {
	a.begin_deployment_snapshot_mode(false)
}

fn (mut a SoftwareApp) begin_deployment_snapshot_mode(media bool) {
	a.clear_deployment_snapshot()
	a.initialize_deployment_field()
	a.deployment_path.clear()
	a.snapshot_mode = true; a.focus = true
	a.snapshot_media = media
	a.set_status(if media { 'Import signed repositories with administrator approval, or save the release lock from media you already imported.' }
		else { 'Choose a new filename for the installed deployment. Existing files are preserved.' })
}

fn (mut a SoftwareApp) media_directory_valid(path string) bool {
	if software_deployment_path_valid(path) { return true }
	a.set_status('Enter an absolute media directory path without control characters (at most 4096 bytes).')
	return false
}

fn (mut a SoftwareApp) import_offline_media() {
	path := editor_bytes_text(a.deployment_path)
	if !a.media_directory_valid(path) { return }
	mut args := []string{cap: 4}
	defer { unsafe { (&array(&args)).free() } }
	args << 'update-media'
	args << path
	if a.snapshot_receipt {
		receipt := editor_bytes_text(a.snapshot_receipt_path)
		if !software_deployment_path_valid(receipt) {
			a.set_status('Enter the absolute path to the ISO package receipt.')
			return
		}
		if a.snapshot_media_sha256.len != 64 {
			a.set_status('Enter all 64 lowercase hex digits from the trusted release checksums.')
			return
		}
		args << receipt
		args << editor_bytes_text(a.snapshot_media_sha256)
	}
	a.start(args, false)
	if a.worker != unsafe { nil } {
		a.clear_failure()
		a.repository_worker = .media_import
		a.focus = false; a.select_all = false
		if !a.admin_prompt { a.set_status('Importing the signed offline repositories…') }
	}
}

fn (mut a SoftwareApp) restore_media_import_fields(args []string) {
	// The worker owns the literal approved arguments until it is retired.
	index := args.index('update-media')
	if index < 0 || index + 1 >= args.len { return }
	software_repository_text(mut a.deployment_path, args[index + 1])
	if args.len == index + 4 {
		software_repository_text(mut a.snapshot_receipt_path, args[index + 2])
		software_repository_text(mut a.snapshot_media_sha256, args[index + 3])
	}
}

fn (mut a SoftwareApp) reload_imported_media_catalog() {
	a.clear_media_receipt()
	a.clear_failure()
	a.offline_requested = true
	mut args := ['view']
	a.start(args, true)
	unsafe { (&array(&args)).free() }
	if a.worker != unsafe { nil } {
		a.repository_worker = .media_catalog
		a.set_status('Media imported. Reloading the offline catalog…')
	} else { a.media_catalog_failed() }
}

fn (mut a SoftwareApp) media_catalog_failed() {
	message := 'Media imported, but the offline catalog could not be reloaded. ' + a.status
	a.set_status(message)
	unsafe { message.free() }
}

fn (mut a SoftwareApp) save_deployment_snapshot() {
	path := editor_bytes_text(a.deployment_path)
	if a.snapshot_media && a.snapshot_media_source == '' {
		if !a.media_directory_valid(path) { return }
		a.snapshot_media_source = path.clone()
		a.deployment_path.clear()
		a.focus = true; a.select_all = false
		a.set_status('Choose a new filename in a writable directory outside the offline media.')
		return
	}
	if !software_deployment_path_valid(path) {
		a.set_status('Enter a new absolute deployment file path without control characters (at most 4096 bytes).')
		return
	}
	if a.snapshot_media && a.snapshot_media_sha256.len !in [0, 64]! {
		a.set_status('Enter 64 lowercase hex digits or leave the SHA-256 field empty.')
		return
	}
	unsafe { a.snapshot_pending.free(); a.snapshot_pending_sha256.free() }
	a.snapshot_pending = path.clone()
	a.snapshot_pending_sha256 = editor_bytes_text(a.snapshot_media_sha256).clone()
	a.focus = false; a.select_all = false
	mut args := []string{cap: 5}
	args << '--json'
	if a.snapshot_media {
		args << 'deployment-media-save'
		args << a.snapshot_media_source
	} else { args << 'deployment-snapshot-save' }
	args << a.snapshot_pending
	if a.snapshot_pending_sha256 != '' { args << a.snapshot_pending_sha256 }
	a.start(args, true)
	unsafe { (&array(&args)).free() }
	if a.worker != unsafe { nil } {
		// This command writes as the desktop user. Its JSON is buffered like a
		// read, but closing/canceling must not kill a possibly publishing writer.
		a.worker_snapshot = true
		a.set_status(if a.snapshot_media { 'Verifying the media lock and saving it to a new file…' }
			else { 'Saving the complete installed deployment to a new file…' })
	}
}

fn (mut a SoftwareApp) prepare_deployment_snapshot_details() {
	a.clear_details()
	a.details_pages = []SoftwareDetailsPage{cap: 16}
	unsafe { a.details_pages.flags |= .noslices }
	media := a.snapshot_media_saved
	installed := a.snapshot_saved
	mut values := ['Saved file: ' + if a.snapshot_media { media.destination } else { installed.destination },
		'Saved bytes SHA-256: ' + if a.snapshot_media { media.sha256 } else { installed.sha256 },
		'Architecture: ' + if a.snapshot_media { media.architecture } else { installed.architecture }]
	unsafe { values.flags |= .noslices }
	if !a.snapshot_media { software_details_count(mut values, 'Installed generation: ', installed.generation) }
	software_details_count(mut values, 'Requested applications: ', if a.snapshot_media { media.roots } else { installed.roots })
	software_details_count(mut values, 'Packages including runtimes: ', if a.snapshot_media { media.packages } else { installed.packages })
	if !a.snapshot_media {
		values << 'Installed metadata only. Payloads, personal data and repository trust are not backed up. Restoring requires a fresh deployment review.'.clone()
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

fn (mut a SoftwareApp) read_deployment_save_receipt(receipt string) ! {
	if a.snapshot_media {
		a.snapshot_media_saved = pkgprotocol.decode_deployment_media_saved(receipt)!
	} else {
		a.snapshot_saved = pkgprotocol.decode_deployment_saved(receipt)!
	}
}

fn (mut a SoftwareApp) load_deployment_snapshot() bool {
	a.read_deployment_save_receipt(editor_bytes_text(a.output)) or {
		unsafe { err.free() }
		a.set_status('Saving returned an invalid or incomplete receipt. The file may exist; inspect the destination before trying a new filename.')
		return false
	}
	destination := if a.snapshot_media { a.snapshot_media_saved.destination } else { a.snapshot_saved.destination }
	if destination != a.snapshot_pending {
		a.snapshot_media_saved.close()
		a.snapshot_saved.close()
		a.set_status('The save receipt names a different destination. The file may exist; inspect the chosen destination before continuing.')
		return false
	}
	if a.snapshot_pending_sha256 != '' && a.snapshot_media_saved.sha256 != a.snapshot_pending_sha256 {
		a.snapshot_media_saved.close()
		a.set_status('The save receipt has a different SHA-256. The file may exist. Check the destination before retrying.')
		return false
	}
	a.snapshot_ready = true
	a.prepare_deployment_snapshot_details()
	a.set_status(if a.snapshot_media { 'Media lock saved. You can disconnect the media and review additions from the saved file.' }
		else { 'Installed deployment saved. Check installed compares metadata; Review deployment prepares changes for your approval.' })
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
		'software.snapshot.back' {
			if a.snapshot_receipt {
				a.clear_media_receipt()
				a.focus = true; a.select_all = false
				a.set_status('Choose how to import the signed media or save its deployment lock.')
			} else { a.clear_deployment_snapshot() }
		}
		'software.snapshot.another' { a.begin_deployment_snapshot_mode(a.snapshot_media) }
		'software.snapshot.export' { if !a.snapshot_media { a.export_deployment_snapshot() } }
		'software.snapshot.import' {
			if a.snapshot_media && a.snapshot_media_source == '' && !a.snapshot_ready { a.import_offline_media() }
		}
		'software.snapshot.import-receipt' {
			if a.snapshot_media && a.snapshot_media_source == '' && !a.snapshot_ready && !a.snapshot_receipt
				&& a.media_directory_valid(editor_bytes_text(a.deployment_path)) {
				a.clear_failure()
				a.snapshot_receipt = true
				a.focus = true; a.select_all = false
				a.set_status('Use the receipt SHA-256 from the trusted release checksums.')
			}
		}
		'software.snapshot.receipt-path' {
			if a.snapshot_receipt { a.focus = true; a.select_all = false; a.snapshot_sha256_focus = false }
		}
		'software.deployment.path' {
			if !a.snapshot_ready && !a.snapshot_receipt { a.focus = true; a.select_all = false; a.snapshot_sha256_focus = false }
		}
		'software.snapshot.sha256' {
			if (a.snapshot_receipt || a.snapshot_media_source != '') && !a.snapshot_ready {
				a.focus = true; a.select_all = false; a.snapshot_sha256_focus = true
			}
		}
		'software.snapshot.save' { if !a.snapshot_ready && !a.snapshot_receipt { a.save_deployment_snapshot() } }
		'software.snapshot.previous' { if a.details_page > 0 { a.details_page-- } }
		'software.snapshot.next' { if a.details_page + 1 < a.details_pages.len { a.details_page++ } }
		'software.snapshot.audit', 'software.snapshot.review' {
			if !a.snapshot_ready { return }
			additions := a.snapshot_media
			expected_sha256 := a.snapshot_media_saved.sha256.clone()
			// Restore the captured literal filename, not the mutable form value.
			a.deployment_path.clear()
			for byte in a.snapshot_pending { a.deployment_path << byte }
			a.clear_deployment_snapshot()
			if event_id == 'software.snapshot.audit' { a.begin_deployment_audit_with_digest(additions, expected_sha256) }
			else { a.begin_deployment_review_with_digest(additions, expected_sha256) }
			unsafe { expected_sha256.free() }
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
	if a.snapshot_ready { return }
	if input == '\t' && (a.snapshot_receipt || a.snapshot_media_source != '') {
		a.handle_deployment_snapshot(if !a.snapshot_sha256_focus { 'software.snapshot.sha256' }
			else if a.snapshot_receipt { 'software.snapshot.receipt-path' } else { 'software.deployment.path' })
		return
	}
	if (a.snapshot_receipt || a.snapshot_sha256_focus) && a.focus {
		match input {
			'\x01' { a.select_all = true }
			'\x08', '\x7f' {
				if a.snapshot_sha256_focus { console_backspace(mut a.snapshot_media_sha256, a.select_all) }
				else { console_backspace(mut a.snapshot_receipt_path, a.select_all) }
				a.select_all = false
			}
			'\r', '\n' { a.focus = false; a.select_all = false }
			else { a.snapshot_paste_input(input) }
		}
		return
	}
	a.deployment_key_input(input)
}

fn (mut a SoftwareApp) snapshot_paste_input(input string) {
	if a.worker != unsafe { nil } || a.snapshot_ready || !a.focus { return }
	if a.snapshot_sha256_focus {
		if input == '' { return }
		length := if a.select_all { 0 } else { a.snapshot_media_sha256.len }
		if input.len > 64 - length {
			a.set_status('The SHA-256 field accepts at most 64 digits. The field was kept intact.')
			return
		}
		for byte in input {
			if !((byte >= `0` && byte <= `9`) || (byte >= `a` && byte <= `f`)) {
				a.set_status('Use lowercase hexadecimal digits. The SHA-256 field was kept intact.')
				return
			}
		}
		if a.snapshot_media_sha256.cap == 0 { a.snapshot_media_sha256 = []u8{cap: 64} }
		if a.select_all { a.snapshot_media_sha256.clear() }
		for byte in input { a.snapshot_media_sha256 << byte }
		a.select_all = false
		return
	}
	if a.snapshot_receipt {
		if input == '' { return }
		length := if a.select_all { 0 } else { a.snapshot_receipt_path.len }
		if input.len > software_deployment_path_limit - length || !software_deployment_text_valid(input) {
			a.set_status('Use a valid receipt path without control characters, up to 4096 bytes.')
			return
		}
		if a.snapshot_receipt_path.cap == 0 { a.snapshot_receipt_path = []u8{cap: software_deployment_path_limit} }
		if a.select_all { a.snapshot_receipt_path.clear() }
		for byte in input { a.snapshot_receipt_path << byte }
		a.select_all = false
		return
	}
	// Pasted controls are filename data, never navigation or editing commands.
	// Refuse the entire paste so filtering cannot silently choose another file.
	if !software_deployment_text_valid(input) {
		a.set_status('The deployment file path contains control characters or invalid UTF-8. The field was kept intact.')
		return
	}
	a.deployment_paste_input(input)
}

fn (a &SoftwareApp) build_snapshot_compact(width int, height int) ui2.Element {
	mut children := frame_elements(9)
	source_step := a.snapshot_media && a.snapshot_media_source == ''
	title := if a.snapshot_media { 'Save media lock' } else { 'Save installed' }
	saved_title := if a.snapshot_media { 'Media lock saved' } else { 'Installed deployment saved' }
	media_progress := a.repository_worker == .media_import && a.progress_seen
	if width < 320 || height < 240 {
		children << software_label(if a.snapshot_media {
			if a.snapshot_ready { 'Media lock saved · enlarge for details' } else { 'Offline media · enlarge for controls' }
		} else {
			if a.snapshot_ready { 'Installed deployment saved · enlarge for details' } else { 'Save installed · enlarge for details' }
		}, 14, 8, width - 28, 28, false)
		if a.worker == unsafe { nil } {
			failure := a.failure_pages.len > 0
			button_width := if failure { (width - 40) / 2 } else { if width > 202 { 174 } else { width - 28 } }
			children << software_button('software.snapshot.back', 'Back', 14, 46, button_width)
			if failure { children << software_button('software.failure', 'Failure', 26 + button_width, 46, button_width) }
		} else {
			children << software_label(if source_step { 'Wait for offline media.' } else { 'Wait for saving to finish.' }, 14, 46, width - 28, 28, false)
		}
		children << software_label(a.status, 14, 78, width - 28, if height > 86 { height - 86 } else { 1 }, false)
		return ui2.screen(app_surface, children)
	}
	if !a.snapshot_ready {
		idle := a.worker == unsafe { nil }
		digest_field := a.snapshot_media && !source_step
		children << software_label(if source_step { 'Offline media' } else { title }, 14, 8, if idle { width - 98 } else { width - 28 }, 28, false)
		if idle { children << software_button('software.snapshot.back', 'Back', width - 70, 8, 56) }
		children << software_label(if source_step { 'Media directory (absolute path)' } else { 'New deployment file (absolute path)' }, 14, 42, width - 28, 18, false)
		children << console_field('software.deployment.path', editor_bytes_text(a.deployment_path), 14, if digest_field { 60 } else { 64 }, width - 28, a.focus && !a.snapshot_sha256_focus)
		if digest_field {
			children << software_label('Expected SHA-256 (optional)', 14, 94, width - 28, 18, false)
			children << console_field('software.snapshot.sha256', editor_bytes_text(a.snapshot_media_sha256), 14, 112, width - 28, a.focus && a.snapshot_sha256_focus)
		}
		action_y := if digest_field { 148 } else { 104 }
		mut status_y := if digest_field { 182 } else { 142 }
		if idle {
			failure := a.failure_pages.len > 0
			button_width := if failure || source_step { (width - 40) / 2 } else { 174 }
			if source_step {
				children << software_button('software.snapshot.import', 'Import media', 14, 104, button_width)
				children << software_button('software.snapshot.save', title, 26 + button_width, 104, button_width)
				children << software_button('software.snapshot.import-receipt', 'Import with receipt…', 14, 142, button_width)
				if failure {
					children << software_button('software.failure', 'Failure details', 26 + button_width, 142, button_width)
				}
				status_y = 180
			} else {
				children << software_button('software.snapshot.save', title, 14, action_y, button_width)
				if failure { children << software_button('software.failure', 'Failure details', 26 + button_width, action_y, button_width) }
			}
		} else {
			children << software_label(if source_step { 'Wait for offline media.' } else { 'Wait for saving to finish.' }, 14, action_y, width - 28, 28, false)
			if media_progress {
				children << a.progress_bar(width, 240)
				status_y = 152
			}
		}
		children << software_label(a.status, 14, status_y, width - 28, height - status_y - 8, false)
		return ui2.screen(app_surface, children)
	}
	children << software_label(saved_title, 14, 8, width - 28, 28, false)
	button_width := if width > 202 { 174 } else { width - 28 }
	available := a.failure_pages.len > 0 && a.worker == unsafe { nil }
	if a.worker == unsafe { nil } {
		children << software_button('software.snapshot.back', 'Back to deployment', 14, 46, button_width)
	} else {
		children << software_label('Wait for saving to finish.', 14, 46, width - 28, 28, false)
	}
	mut next_y := 84
	if a.worker == unsafe { nil } && a.snapshot_ready && height >= 220 {
		receipt_width := if a.snapshot_media { (width - 40) / 2 } else { button_width }
		children << software_button('software.report.read', 'Read receipt', 14, next_y, receipt_width)
		if a.snapshot_media {
			children << software_button('software.snapshot.review', 'Review additions', 26 + receipt_width, next_y, receipt_width)
		}
		next_y += 38
	}
	if available { children << software_button('software.failure', 'Failure details', 14, next_y, button_width); next_y += 38 }
	preferred_y := if height > 230 { height - 98 } else { next_y }
	y := if preferred_y > next_y { preferred_y } else { next_y }
	children << software_label(a.status, 14, y, width - 28, if height > y + 8 { height - y - 8 } else { 1 }, false)
	return ui2.screen(app_surface, children)
}

fn (a &SoftwareApp) build_media_receipt(width int, height int) ui2.Element {
	mut children := frame_elements(12)
	compact := width < 640 || height < 610
	idle := a.worker == unsafe { nil }
	fields_y := if compact { 42 } else { 94 }
	action_y := fields_y + 106
	children << software_label('Import with ISO receipt', 14, 8, if compact && idle { width - 98 } else { width - 28 }, 28, false)
	if idle {
		children << software_button('software.snapshot.back', 'Back', if compact { width - 70 } else { 14 },
			if compact { 8 } else { 46 }, if compact { 56 } else { 112 })
	}
	children << software_label('ISO receipt file (absolute path)', 14, fields_y, width - 28, 18, false)
	children << console_field('software.snapshot.receipt-path', editor_bytes_text(a.snapshot_receipt_path),
		14, fields_y + 18, width - 28, a.focus && !a.snapshot_sha256_focus)
	children << software_label('Receipt SHA-256', 14, fields_y + 52, width - 28, 18, false)
	children << console_field('software.snapshot.sha256', editor_bytes_text(a.snapshot_media_sha256),
		14, fields_y + 70, width - 28, a.focus && a.snapshot_sha256_focus)
	if idle {
		button_width := if compact && a.failure_pages.len > 0 { (width - 40) / 2 } else { 174 }
		children << software_button('software.snapshot.import', 'Import media', 14, action_y, button_width)
		if compact && a.failure_pages.len > 0 {
			children << software_button('software.failure', 'Failure details', 26 + button_width, action_y, button_width)
		}
	} else { children << software_label('Wait for offline media.', 14, action_y, width - 28, 28, false) }
	progress := a.repository_worker == .media_import && a.progress_seen
	if progress { children << a.progress_bar(width, if compact { 280 } else { height }) }
	if compact {
		status_y := if progress { 192 } else { 182 }
		children << software_label(a.status, 14, status_y, width - 28, height - status_y - 8, false)
	} else { a.add_status_footer(mut children, width, height, progress) }
	return ui2.screen(app_surface, children)
}

fn (mut a SoftwareApp) build_deployment_snapshot(width int, height int) ui2.Element {
	if a.snapshot_receipt && width >= 320 && height >= 240 { return a.build_media_receipt(width, height) }
	if width < 640 || height < 610 { return a.build_snapshot_compact(width, height) }
	mut children := frame_elements(28)
	source_step := a.snapshot_media && a.snapshot_media_source == ''
	title := if source_step { 'Offline media' } else if a.snapshot_media { 'Save media lock' } else { 'Save installed deployment' }
	children << software_label(title, 14, 8, width - 28, 28, false)
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
		children << software_button('software.snapshot.audit', if a.snapshot_media { 'Check coverage' } else { 'Check installed' }, 14, height - 130, 180)
		children << software_button('software.snapshot.review', if a.snapshot_media { 'Review additions' } else { 'Review deployment' }, 210, height - 130, 180)
		if !a.snapshot_media && a.snapshot_saved.packages > 0 {
			children << software_button('software.snapshot.export', 'Export offline…', 406, height - 130, 180)
		}
	} else {
		children << software_label(if source_step { 'Offline media directory (absolute path)' } else { 'New deployment file (absolute path)' }, 14, 94, width - 28, 28, false)
		children << console_field('software.deployment.path', editor_bytes_text(a.deployment_path), 14, 128, width - 28, a.focus && !a.snapshot_sha256_focus)
		if a.snapshot_media {
			if source_step {
				children << software_label('Import a bundle controlled by your administrator. Software uses enrolled publisher keys to check the signed repositories and cache packages from the media.', 14, 174, width - 28, 60, false)
			} else {
				children << software_label('Expected SHA-256 (optional)', 14, 200, width - 28, 28, false)
				children << console_field('software.snapshot.sha256', editor_bytes_text(a.snapshot_media_sha256), 14, 232, width - 28, a.focus && a.snapshot_sha256_focus)
				children << software_label('Choose a new filename outside the media. To require the exact release lock, enter deployment_sha256 from the trusted release receipt.', 14, 280, width - 28, 54, false)
			}
		} else {
			children << software_label('Save all installed applications and their exact recorded dependencies, runtimes and requested roots. Choose a new filename in a directory you can write. Existing files will never be replaced.', 14, 174, width - 28, 60, false)
			children << software_label('This saves metadata, not application payloads or personal data. Restoring needs trusted repositories or offline media, explicit license consent and a fresh review.', 14, 246, width - 28, 60, false)
		}
		if a.worker == unsafe { nil } {
			if source_step {
				children << software_button('software.snapshot.import', 'Import media', 14, 326, 180)
				children << software_button('software.snapshot.import-receipt', 'Import with receipt…', 406, 326, 180)
			}
			children << software_button('software.snapshot.save', if a.snapshot_media { 'Save media lock' } else { 'Save installed' }, if source_step { 210 } else { 14 }, if a.snapshot_media && !source_step { 348 } else { 326 }, 180)
		}
	}
	progress := a.repository_worker == .media_import && a.progress_seen
	if progress { children << a.progress_bar(width, height) }
	a.add_status_footer(mut children, width, height, progress)
	return ui2.screen(app_surface, children)
}
