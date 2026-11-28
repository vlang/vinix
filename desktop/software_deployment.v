// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import encoding.utf8

const software_deployment_path_limit = 4096

fn software_deployment_text_valid(text string) bool {
	if !utf8.validate_str(text) { return false }
	for i, byte in text {
		if byte < 32 || byte == 127 || (byte == 0xc2 && i + 1 < text.len && text[i + 1] <= 0x9f) {
			return false
		}
	}
	return true
}

fn software_deployment_path_valid(path string) bool {
	return path.len > 0 && path.len <= software_deployment_path_limit && path[0] == `/`
		&& software_deployment_text_valid(path)
}

fn (mut a SoftwareApp) initialize_deployment_field() {
	if a.deployment_path.cap == 0 {
		a.deployment_path = []u8{cap: software_deployment_path_limit}
	}
	unsafe { a.deployment_path.flags |= .noslices }
}

fn (mut a SoftwareApp) begin_deployment_review() {
	digest := a.saved_media_deployment_digest()
	a.begin_deployment_review_with_digest(digest != '', digest)
}

fn (a &SoftwareApp) saved_media_deployment_digest() string {
	return if editor_bytes_text(a.deployment_path) == a.deployment_saved_media_path {
		a.deployment_saved_media_sha256
	} else { '' }
}

fn (mut a SoftwareApp) clear_saved_media_deployment() {
	unsafe { a.deployment_saved_media_path.free(); a.deployment_saved_media_sha256.free() }
	a.deployment_saved_media_path = ''
	a.deployment_saved_media_sha256 = ''
}

fn (mut a SoftwareApp) begin_deployment_review_mode(additions bool) {
	a.begin_deployment_review_with_digest(additions, '')
}

fn (mut a SoftwareApp) begin_deployment_review_with_digest(additions bool, expected_sha256 string) {
	a.initialize_deployment_field()
	a.clear_review()
	path := editor_bytes_text(a.deployment_path)
	if !software_deployment_path_valid(path) {
		a.set_status('Enter an absolute deployment file path without control characters (at most 4096 bytes).')
		return
	}
	a.review = if additions { 'deploy-add'.clone() } else { 'deploy'.clone() }
	a.deployment_pending = path.clone()
	a.deployment_pending_sha256 = expected_sha256.clone()
	a.focus = false
	a.select_all = false
	mut args := []string{cap: 3}
	args << if additions { 'deployment-add-review' } else { 'deployment-review' }
	args << a.deployment_pending
	if a.deployment_pending_sha256 != '' { args << a.deployment_pending_sha256 }
	a.start(args, false)
	unsafe { (&array(&args)).free() }
	if a.worker != unsafe { nil } {
		a.worker_review = true
		a.set_status('Checking the deployment file, trusted publishers, dependencies, policy and disk space…')
	} else {
		a.clear_review()
	}
}

fn (mut a SoftwareApp) handle_deployment(event_id string) {
	match event_id {
		'software.deployment.action.previous' { a.navigate_deployment_form(-1) }
		'software.deployment.action.next' { a.navigate_deployment_form(1) }
		'software.deployment.choose' { a.choose_deployment_file() }
		'software.deployment.release' { a.open_release_deployment_review() }
		'software.deployment.release-add' { a.open_release_deployment_review_mode(true) }
		'software.deployment.release-audit' { a.audit_release_deployment(false) }
		'software.deployment.release-coverage' { a.audit_release_deployment(true) }
		'software.deployment.path' {
			a.focus = true
			a.select_all = false
		}
		'software.deployment.review' { a.begin_deployment_review() }
		'software.deployment.audit' { a.begin_deployment_audit() }
		'software.deployment.snapshot' { a.begin_deployment_snapshot() }
		'software.deployment.media-save' { a.begin_deployment_snapshot_mode(true) }
		'software.deployment.back' {
			a.deployment_mode = false
			a.focus = false
			a.select_all = false
			a.set_status('Select an application to review its publisher, license and permissions.')
		}
		else {}
	}
}

fn (mut a SoftwareApp) deployment_key_input(input string) {
	if input == '\x1b' {
		if a.deployment_review_running() { a.stop_deployment_review(); return }
		if a.worker == unsafe { nil } {
			if a.review != '' {
				a.clear_review()
				a.set_status('Deployment review cancelled before starting changes.')
				return
			}
			if !a.focus { a.handle_deployment('software.deployment.back'); return }
		}
	}
	if !a.focus && a.deployment_form_compact && a.deployment_form_idle() {
		match input {
			'\x1b[D', '\x1b[5~' { a.navigate_deployment_form(-1); return }
			'\x1b[C', '\x1b[6~' { a.navigate_deployment_form(1); return }
			else {}
		}
	}
	// A pending review or transaction owns its literal path. Editing is only
	// possible in the form, after cancellation/failure or before review.
	if !a.focus || a.review != '' || a.worker != unsafe { nil } { return }
	match input {
		'\x01' { a.select_all = true }
		'\x7f', '\x08' {
			console_backspace(mut a.deployment_path, a.select_all)
			a.select_all = false
		}
		'\x1b', '\r', '\n' { a.focus = false }
		else { a.deployment_paste_input(input) }
	}
}

fn (mut a SoftwareApp) deployment_paste_input(input string) {
	if !a.focus || a.review != '' || a.worker != unsafe { nil } || input.len == 0 { return }
	length := if a.select_all { 0 } else { a.deployment_path.len }
	if input.len > software_deployment_path_limit - length {
		a.set_status('The deployment file path exceeds 4096 bytes. The field was kept intact.')
		return
	}
	// Clipboard text is a literal filename, never navigation or editing keys.
	// Refuse it as a whole rather than silently selecting a different file.
	if !software_deployment_text_valid(input) {
		a.set_status('The deployment file path contains control characters or invalid UTF-8. The field was kept intact.')
		return
	}
	a.initialize_deployment_field()
	if a.select_all { a.deployment_path.clear() }
	for byte in input { a.deployment_path << byte }
	a.select_all = false
}

fn (mut a SoftwareApp) build_deployment(width int, height int) ui2.Element {
	a.deployment_form_compact = false
	a.initialize_deployment_field()
	// Include the actions, progress and failure controls without growing
	// the manual-free frame buffer on each redraw.
	mut children := frame_elements(21)
	pinned_media := a.saved_media_deployment_digest() != ''
	children << software_label('Software · Deployment', 14, 8, width - 188, 28, false)
	if a.worker == unsafe { nil } {
		children << software_button('software.deployment.back', 'Back to catalog', width - 174, 8, 160)
	}
	children << software_label(if pinned_media { 'Saved media lock (SHA-256 required)' }
		else { 'Deployment file (absolute path)' }, 14, 52, width - 28, 28, false)
	children << console_field('software.deployment.path', editor_bytes_text(a.deployment_path), 14, 86, width - 202, a.focus)
	if a.deployment_choice_pending {
		children << software_label('Choosing file…', width - 174, 86, 160, 28, false)
	} else if a.worker == unsafe { nil } {
		children << software_button('software.deployment.choose', 'Choose file…', width - 174, 86, 160)
	}
	children << software_label(if pinned_media {
		'Check coverage compares the saved release with installed metadata. Review additions keeps your existing application selections.'
	} else { 'Use a deployment file supplied by your organization. Check installed compares an exact lock with recorded installed metadata. Review deployment checks the full application set before any changes.' }, 14, 128, width - 28, 60, false)
	children << software_label(if pinned_media {
		'Software checks the saved SHA-256, publisher trust and organization policy. Applying the reviewed changes requires separate approval.'
	} else { 'The review includes installs, retained packages, updates and removals, with publisher keys, permissions, licenses and disk requirements. Empty deployments remove all packages. Personal data stays on disk.' }, 14, 204, width - 28, 60, false)
	if a.worker == unsafe { nil } {
		children << software_button('software.deployment.review', if pinned_media { 'Review additions' } else { 'Review deployment' }, 14, 286, 180)
		children << software_button('software.deployment.audit', if pinned_media { 'Check coverage' } else { 'Check installed' }, 210, 286, 160)
		children << software_button('software.policy', 'Organization policy', 14, 330, 180)
		children << software_button('software.deployment.snapshot', 'Save installed…', 210, 330, 160)
		children << software_button('software.deployment.media-save', 'Offline media…', 386, 330, 184)
		if a.release_deployment_available {
			children << software_button('software.deployment.release', 'Review release apps', 14, 374, 180)
			children << software_button('software.deployment.release-audit', 'Check release apps', 210, 374, 160)
			children << software_button('software.deployment.release-add', 'Add release apps', 14, 418, 180)
			children << software_button('software.deployment.release-coverage', 'Check release coverage', 210, 418, 160)
		}
	} else if a.deployment_review_running() {
		children << software_button('software.deployment.stop', 'Stop review', 14, 286, 160)
	}
	if a.progress_seen { children << a.progress_bar(width, height) }
	a.add_status_footer(mut children, width, height, a.progress_seen)
	return ui2.screen(app_surface, children)
}
