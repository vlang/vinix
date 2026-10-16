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
	a.initialize_deployment_field()
	a.clear_review()
	path := editor_bytes_text(a.deployment_path)
	if !software_deployment_path_valid(path) {
		a.set_status('Enter an absolute deployment file path without control characters (at most 4096 bytes).')
		return
	}
	a.review = 'deploy'.clone()
	a.deployment_pending = path.clone()
	a.focus = false
	a.select_all = false
	a.start(['deployment-review', a.deployment_pending], false)
	if a.worker != unsafe { nil } {
		a.worker_review = true
		a.set_status('Checking the deployment file, trusted publishers, dependencies, policy and disk space…')
	} else {
		a.clear_review()
	}
}

fn (mut a SoftwareApp) handle_deployment(event_id string) {
	match event_id {
		'software.deployment.choose' { a.choose_deployment_file() }
		'software.deployment.release' { a.review_release_deployment() }
		'software.deployment.release-audit' { a.audit_release_deployment() }
		'software.deployment.path' {
			a.focus = true
			a.select_all = false
		}
		'software.deployment.review' { a.begin_deployment_review() }
		'software.deployment.audit' { a.begin_deployment_audit() }
		'software.deployment.snapshot' { a.begin_deployment_snapshot() }
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
	a.initialize_deployment_field()
	// Include all four actions, progress and failure controls without growing
	// the manual-free frame buffer on each redraw.
	mut children := frame_elements(20)
	children << software_label('Software · Deployment', 14, 8, width - 188, 28, false)
	if a.worker == unsafe { nil } {
		children << software_button('software.deployment.back', 'Back to catalog', width - 174, 8, 160)
	}
	children << software_label('Deployment file (absolute path)', 14, 52, width - 28, 28, false)
	children << console_field('software.deployment.path', editor_bytes_text(a.deployment_path), 14, 86, width - 202, a.focus)
	if a.deployment_choice_pending {
		children << software_label('Choosing file…', width - 174, 86, 160, 28, false)
	} else if a.worker == unsafe { nil } {
		children << software_button('software.deployment.choose', 'Choose file…', width - 174, 86, 160)
	}
	children << software_label('Use a deployment file supplied by your organization. Check installed compares an exact lock with recorded installed metadata. Review deployment checks the full application set before any changes.', 14, 128, width - 28, 60, false)
	children << software_label('The review includes installs, retained packages, updates and removals, with publisher keys, permissions, licenses and disk requirements. Empty deployments remove all packages. Personal data stays on disk.', 14, 204, width - 28, 60, false)
	if a.worker == unsafe { nil } {
		children << software_button('software.deployment.review', 'Review deployment', 14, 286, 180)
		children << software_button('software.deployment.audit', 'Check installed', 210, 286, 160)
		children << software_button('software.policy', 'Organization policy', 14, 330, 180)
		children << software_button('software.deployment.snapshot', 'Save installed…', 210, 330, 160)
		if a.release_deployment_available {
			children << software_button('software.deployment.release', 'Review release apps', 14, 374, 180)
			children << software_button('software.deployment.release-audit', 'Check release apps', 210, 374, 160)
		}
	} else if a.deployment_review_running() {
		children << software_button('software.deployment.stop', 'Stop review', 14, 286, 160)
	}
	if a.progress_seen { children << a.progress_bar(width, height) }
	a.add_status_footer(mut children, width, height, a.progress_seen)
	return ui2.screen(app_surface, children)
}
